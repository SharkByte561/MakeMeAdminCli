#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the MakeMeAdminCLI background service.

.DESCRIPTION
    The Install-MakeMeAdminService cmdlet configures the background service
    components required for MakeMeAdminCLI to function. This is a one-time
    setup step that must be run from an elevated PowerShell session.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.1.0
#>

function Install-MakeMeAdminService {
    <#
    .SYNOPSIS
        Installs the MakeMeAdminCLI background service.

    .DESCRIPTION
        Configures all service components required for MakeMeAdminCLI to function:
        - Creates the state directory at $env:ProgramData\MakeMeAdminCLI\
        - Copies the default config.json to the state directory
        - Initializes the state.json tracking file
        - Registers the Windows Event Log source
        - Creates a scheduled task folder under Task Scheduler
        - Registers and starts the MakeMeAdminCLI-Service scheduled task

        The scheduled task runs Private\Service-Main.ps1 as NT AUTHORITY\SYSTEM
        at startup. It listens on a named pipe for elevation requests from
        standard users.

        This cmdlet requires administrator privileges. It must be run once after
        installing the module via Install-Module.

    .PARAMETER Force
        Reinstalls the service even if it is already configured. Existing
        configuration is preserved unless the config.json is missing.

    .OUTPUTS
        PSCustomObject with installation status for each component:
        - StateDirectory: Boolean
        - ConfigFile: Boolean
        - StateFile: Boolean
        - EventLogSource: Boolean
        - ScheduledTaskFolder: Boolean
        - ScheduledTask: Boolean
        - ServiceStarted: Boolean
        - OverallSuccess: Boolean

    .EXAMPLE
        Install-MakeMeAdminService

        Performs a standard installation of the service components.

    .EXAMPLE
        Install-MakeMeAdminService -Force

        Reinstalls the service, recreating the scheduled task even if it
        already exists.

    .EXAMPLE
        Install-MakeMeAdminService -Verbose

        Installs with detailed progress output.

    .LINK
        Uninstall-MakeMeAdminService
        Test-MakeMeAdminService
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'

    # --- Constants ---
    $ModuleName       = 'MakeMeAdminCLI'
    $TaskName         = 'MakeMeAdminCLI-Service'
    $TaskPath         = '\Microsoft\Windows\MakeMeAdminCLI\'
    $EventLogSource   = 'MakeMeAdminCLI'
    $StateDirectory   = Join-Path $env:ProgramData $ModuleName
    $ConfigFilePath   = Join-Path $StateDirectory 'config.json'
    $StateFilePath    = Join-Path $StateDirectory 'state.json'

    # Determine module root from the script location
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

    # --- Result tracker ---
    $result = [ordered]@{
        StateDirectory      = $false
        ConfigFile          = $false
        StateFile           = $false
        EventLogSource      = $false
        ScheduledTaskFolder = $false
        ScheduledTask       = $false
        ServiceStarted      = $false
        OverallSuccess      = $false
    }

    #region Elevation Check

    if (-not (Test-IsElevated)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Install-MakeMeAdminService must be run from an elevated (Administrator) PowerShell session.'
                ),
                'ElevationRequired',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )
        )
        return
    }

    #endregion

    #region Pre-flight: check for existing installation

    $existingTask = $null
    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    }
    catch {
        # Task doesn't exist, that's fine
    }

    if ($existingTask -and -not $Force) {
        Write-Warning "MakeMeAdminCLI service is already installed. Use -Force to reinstall."
        # Still return current status
        $result.StateDirectory      = Test-Path $StateDirectory
        $result.ConfigFile          = Test-Path $ConfigFilePath
        $result.StateFile           = Test-Path $StateFilePath
        $result.EventLogSource      = $true
        $result.ScheduledTaskFolder = $true
        $result.ScheduledTask       = $true
        $result.ServiceStarted      = $existingTask.State -eq 'Running'
        $result.OverallSuccess      = $true
        return [PSCustomObject]$result
    }

    #endregion

    #region Stop existing service if running

    if ($existingTask -and $existingTask.State -eq 'Running') {
        Write-Verbose 'Stopping existing service scheduled task...'
        try {
            Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Verbose "Could not stop existing task: $($_.Exception.Message)"
        }
    }

    #endregion

    #region Step 1: Create state directory

    if ($PSCmdlet.ShouldProcess($StateDirectory, 'Create state directory')) {
        try {
            if (-not (Test-Path $StateDirectory)) {
                New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
                Write-Verbose "Created state directory: $StateDirectory"
            }
            else {
                Write-Verbose "State directory already exists: $StateDirectory"
            }

            # Create Scripts subdirectory for removal scripts
            $scriptsDir = Join-Path $StateDirectory 'Scripts'
            if (-not (Test-Path $scriptsDir)) {
                New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
                Write-Verbose "Created scripts directory: $scriptsDir"
            }

            $result.StateDirectory = $true
        }
        catch {
            Write-Warning "Failed to create state directory: $($_.Exception.Message)"
        }
    }

    #endregion

    #region Step 2: Copy config.json

    if ($PSCmdlet.ShouldProcess($ConfigFilePath, 'Deploy default configuration')) {
        try {
            $sourceConfig = Join-Path $moduleRoot 'config.json'

            if (-not (Test-Path $ConfigFilePath) -or $Force) {
                if (Test-Path $sourceConfig) {
                    Copy-Item -Path $sourceConfig -Destination $ConfigFilePath -Force
                    Write-Verbose "Deployed config.json to $ConfigFilePath"
                }
                else {
                    Write-Warning "Default config.json not found at $sourceConfig"
                }
            }
            else {
                Write-Verbose "Config.json already exists at $ConfigFilePath (use -Force to overwrite)"
            }

            $result.ConfigFile = Test-Path $ConfigFilePath
        }
        catch {
            Write-Warning "Failed to deploy config.json: $($_.Exception.Message)"
        }
    }

    #endregion

    #region Step 3: Initialize state.json

    if ($PSCmdlet.ShouldProcess($StateFilePath, 'Initialize state file')) {
        try {
            if (-not (Test-Path $StateFilePath)) {
                $initialState = @{
                    ActiveUsers      = @()
                    LastUpdated      = (Get-Date).ToString('o')
                    ServiceStartTime = $null
                }
                $initialState | ConvertTo-Json -Depth 10 |
                    Set-Content -Path $StateFilePath -Encoding UTF8 -Force
                Write-Verbose "Initialized state.json at $StateFilePath"
            }
            else {
                Write-Verbose "state.json already exists at $StateFilePath"
            }

            $result.StateFile = Test-Path $StateFilePath
        }
        catch {
            Write-Warning "Failed to initialize state.json: $($_.Exception.Message)"
        }
    }

    #endregion

    #region Step 4: Register Event Log source

    if ($PSCmdlet.ShouldProcess("Application log source '$EventLogSource'", 'Register Event Log source')) {
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
                [System.Diagnostics.EventLog]::CreateEventSource($EventLogSource, 'Application')
                Start-Sleep -Milliseconds 500
                Write-Verbose "Registered Event Log source '$EventLogSource'"
            }
            else {
                Write-Verbose "Event Log source '$EventLogSource' already registered"
            }

            $result.EventLogSource = $true
        }
        catch {
            Write-Warning "Could not register Event Log source: $($_.Exception.Message)"
            # Non-fatal
        }
    }

    #endregion

    #region Step 5: Create scheduled task folder

    if ($PSCmdlet.ShouldProcess($TaskPath, 'Create Task Scheduler folder')) {
        try {
            $schedule = New-Object -ComObject Schedule.Service
            $schedule.Connect()

            try {
                $null = $schedule.GetFolder($TaskPath)
                Write-Verbose "Task Scheduler folder already exists: $TaskPath"
            }
            catch {
                # Create the folder hierarchy
                $pathParts = $TaskPath.Trim('\').Split('\')
                $currentPath = '\'
                foreach ($part in $pathParts) {
                    $nextPath = "$currentPath$part"
                    try {
                        $null = $schedule.GetFolder($nextPath)
                    }
                    catch {
                        $parentFolder = $schedule.GetFolder($currentPath.TrimEnd('\'))
                        $null = $parentFolder.CreateFolder($part)
                    }
                    $currentPath = "$nextPath\"
                }
                Write-Verbose "Created Task Scheduler folder: $TaskPath"
            }

            $result.ScheduledTaskFolder = $true
        }
        catch {
            Write-Warning "Failed to create Task Scheduler folder: $($_.Exception.Message)"
        }
    }

    #endregion

    #region Step 6: Register the scheduled task

    if ($PSCmdlet.ShouldProcess("$TaskPath$TaskName", 'Register scheduled task')) {
        try {
            # Remove existing task if present (Force path)
            $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
                Write-Verbose 'Removed existing scheduled task'
            }

            # Build the path to Service-Main.ps1 from the installed module location
            $servicePath = Join-Path $moduleRoot 'Private\Service-Main.ps1'

            $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
                -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$servicePath`""

            $trigger = New-ScheduledTaskTrigger -AtStartup

            $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
                -LogonType ServiceAccount `
                -RunLevel Highest

            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -RestartCount 3 `
                -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit (New-TimeSpan -Days 365) `
                -Priority 4 `
                -Hidden

            $null = Register-ScheduledTask -TaskName $TaskName `
                -TaskPath $TaskPath `
                -Action $action `
                -Trigger $trigger `
                -Principal $principal `
                -Settings $settings `
                -Description 'MakeMeAdminCLI service - Provides temporary administrator rights to users'

            Write-Verbose 'Registered scheduled task'
            $result.ScheduledTask = $true
        }
        catch {
            Write-Warning "Failed to register scheduled task: $($_.Exception.Message)"
        }
    }

    #endregion

    #region Step 7: Start the service

    if ($result.ScheduledTask -and $PSCmdlet.ShouldProcess($TaskName, 'Start scheduled task')) {
        try {
            Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
            Start-Sleep -Seconds 2

            $taskInfo = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
            if ($taskInfo.State -eq 'Running') {
                Write-Verbose 'MakeMeAdminCLI service started successfully'
                $result.ServiceStarted = $true
            }
            else {
                Write-Warning "Service task started but current state is: $($taskInfo.State)"
            }
        }
        catch {
            Write-Warning "Could not start service immediately: $($_.Exception.Message). The service will start automatically on next boot."
        }
    }

    #endregion

    # Determine overall success
    $result.OverallSuccess = $result.StateDirectory -and
                             $result.ConfigFile -and
                             $result.StateFile -and
                             $result.ScheduledTask

    return [PSCustomObject]$result
}

# Export the function
Export-ModuleMember -Function 'Install-MakeMeAdminService'
