#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls the MakeMeAdminCLI background service.

.DESCRIPTION
    The Uninstall-MakeMeAdminService cmdlet removes all service components
    that were configured by Install-MakeMeAdminService.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.1.0
#>

function Uninstall-MakeMeAdminService {
    <#
    .SYNOPSIS
        Uninstalls the MakeMeAdminCLI background service.

    .DESCRIPTION
        Removes the service components configured by Install-MakeMeAdminService:
        - Stops and unregisters the MakeMeAdminCLI-Service scheduled task
        - Removes the Task Scheduler folder if empty
        - Optionally removes active elevated users from the Administrators group
        - Removes the Windows Event Log source
        - Removes the state directory (config.json, state.json, removal scripts)

        This cmdlet does NOT remove the module itself from Program Files.
        Use Uninstall-Module MakeMeAdminCLI for that.

        This cmdlet requires administrator privileges.

    .PARAMETER KeepConfig
        If specified, preserves the configuration and state directory at
        $env:ProgramData\MakeMeAdminCLI\. Useful when reinstalling.

    .PARAMETER RemoveActiveUsers
        If specified, removes any currently elevated users from the local
        Administrators group before uninstalling. Without this switch,
        active elevated users retain their admin rights.

    .PARAMETER Force
        Skips the confirmation prompt.

    .OUTPUTS
        PSCustomObject with uninstallation status for each component:
        - ScheduledTaskStopped: Boolean
        - ScheduledTaskRemoved: Boolean
        - TaskFolderRemoved: Boolean
        - ActiveUsersRemoved: Boolean or 'Skipped'
        - EventLogSourceRemoved: Boolean
        - StateDirectoryRemoved: Boolean or 'Kept'
        - OverallSuccess: Boolean

    .EXAMPLE
        Uninstall-MakeMeAdminService

        Uninstalls the service with confirmation prompt.

    .EXAMPLE
        Uninstall-MakeMeAdminService -Force

        Uninstalls the service without prompting for confirmation.

    .EXAMPLE
        Uninstall-MakeMeAdminService -KeepConfig

        Uninstalls the service but preserves config and state files.

    .EXAMPLE
        Uninstall-MakeMeAdminService -RemoveActiveUsers -Force

        Uninstalls and removes any currently elevated users from the
        Administrators group.

    .LINK
        Install-MakeMeAdminService
        Test-MakeMeAdminService
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [switch]$KeepConfig,
        [switch]$RemoveActiveUsers,
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'

    # --- Constants ---
    $ModuleName     = 'MakeMeAdminCLI'
    $TaskName       = 'MakeMeAdminCLI-Service'
    $TaskPath       = '\Microsoft\Windows\MakeMeAdminCLI\'
    $EventLogSource = 'MakeMeAdminCLI'
    $StateDirectory = Join-Path $env:ProgramData $ModuleName
    $StateFilePath  = Join-Path $StateDirectory 'state.json'

    # --- Result tracker ---
    $result = [ordered]@{
        ScheduledTaskStopped  = $false
        ScheduledTaskRemoved  = $false
        TaskFolderRemoved     = $false
        ActiveUsersRemoved    = 'Skipped'
        EventLogSourceRemoved = $false
        StateDirectoryRemoved = 'Kept'
        OverallSuccess        = $false
    }

    #region Elevation Check

    if (-not (Test-IsElevated)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new(
                    'Uninstall-MakeMeAdminService must be run from an elevated (Administrator) PowerShell session.'
                ),
                'ElevationRequired',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )
        )
        return
    }

    #endregion

    # If -Force was specified, override ConfirmPreference so ShouldProcess passes
    if ($Force) {
        $ConfirmPreference = 'None'
    }

    if (-not $PSCmdlet.ShouldProcess('MakeMeAdminCLI service', 'Uninstall')) {
        return
    }

    #region Step 1: Stop and remove the scheduled task

    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue

        if ($existingTask) {
            # Stop the task if running
            if ($existingTask.State -eq 'Running') {
                Write-Verbose 'Stopping scheduled task...'
                Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $result.ScheduledTaskStopped = $true
            }
            else {
                Write-Verbose 'Scheduled task was not running'
                $result.ScheduledTaskStopped = $true
            }

            # Unregister the task
            Write-Verbose 'Unregistering scheduled task...'
            Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
            $result.ScheduledTaskRemoved = $true
            Write-Verbose 'Scheduled task removed'
        }
        else {
            Write-Verbose 'Scheduled task not found (already removed)'
            $result.ScheduledTaskStopped = $true
            $result.ScheduledTaskRemoved = $true
        }
    }
    catch {
        Write-Warning "Could not remove scheduled task: $($_.Exception.Message)"
    }

    #endregion

    #region Step 2: Remove task folder if empty

    try {
        $schedule = New-Object -ComObject Schedule.Service
        $schedule.Connect()

        try {
            $folder = $schedule.GetFolder($TaskPath)
            $tasks = $folder.GetTasks(0)

            if ($tasks.Count -eq 0) {
                $parentPath = Split-Path $TaskPath.TrimEnd('\') -Parent
                if ([string]::IsNullOrEmpty($parentPath) -or $parentPath -eq '\') {
                    $parentPath = '\'
                }
                $parentFolder = $schedule.GetFolder($parentPath)
                $folderName = Split-Path $TaskPath.TrimEnd('\') -Leaf
                $parentFolder.DeleteFolder($folderName, 0)
                $result.TaskFolderRemoved = $true
                Write-Verbose "Removed empty task folder: $TaskPath"
            }
            else {
                Write-Verbose "Task folder not empty ($($tasks.Count) remaining tasks), leaving in place"
                $result.TaskFolderRemoved = $false
            }
        }
        catch {
            # Folder may not exist
            Write-Verbose "Task folder not found or already removed"
            $result.TaskFolderRemoved = $true
        }
    }
    catch {
        Write-Verbose "Could not check task folder: $($_.Exception.Message)"
    }

    #endregion

    #region Step 3: Remove active elevated users (optional)

    if ($RemoveActiveUsers) {
        try {
            $activeUsers = @()

            if (Test-Path $StateFilePath) {
                try {
                    $state = Get-Content -Path $StateFilePath -Raw | ConvertFrom-Json
                    if ($state.ActiveUsers) {
                        $activeUsers = @($state.ActiveUsers)
                    }
                }
                catch {
                    Write-Verbose "Could not read state file: $($_.Exception.Message)"
                }
            }

            if ($activeUsers.Count -gt 0) {
                Write-Verbose "Found $($activeUsers.Count) active elevated user(s)"

                # Get the local Administrators group by SID (language-independent)
                $adminGroupSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
                $adminGroup = $adminGroupSid.Translate([System.Security.Principal.NTAccount]).Value
                $localAdminGroup = [ADSI]"WinNT://./$($adminGroup.Split('\')[-1]),group"

                foreach ($user in $activeUsers) {
                    try {
                        $members = @($localAdminGroup.Invoke('Members') | ForEach-Object {
                            $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
                        })

                        $usernameShort = $user.Username -replace '^[^\\]+\\', ''

                        if ($members -contains $usernameShort) {
                            $localAdminGroup.Remove("WinNT://$($user.Username)")
                            Write-Verbose "Removed '$($user.Username)' from Administrators group"
                        }
                        else {
                            Write-Verbose "'$($user.Username)' is not currently in Administrators group"
                        }
                    }
                    catch {
                        Write-Warning "Could not remove '$($user.Username)' from Administrators: $($_.Exception.Message)"
                    }
                }

                $result.ActiveUsersRemoved = $true
            }
            else {
                Write-Verbose 'No active elevated users to remove'
                $result.ActiveUsersRemoved = $true
            }
        }
        catch {
            Write-Warning "Could not process active users: $($_.Exception.Message)"
            $result.ActiveUsersRemoved = $false
        }
    }

    #endregion

    #region Step 4: Remove Event Log source

    try {
        if ([System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
            [System.Diagnostics.EventLog]::DeleteEventSource($EventLogSource)
            Write-Verbose "Removed Event Log source '$EventLogSource'"
            $result.EventLogSourceRemoved = $true
        }
        else {
            Write-Verbose "Event Log source '$EventLogSource' not found"
            $result.EventLogSourceRemoved = $true
        }
    }
    catch {
        Write-Warning "Could not remove Event Log source: $($_.Exception.Message)"
    }

    #endregion

    #region Step 5: Remove state directory

    if ($KeepConfig) {
        Write-Verbose "Keeping state directory at $StateDirectory (-KeepConfig specified)"
        $result.StateDirectoryRemoved = 'Kept'
    }
    else {
        try {
            if (Test-Path $StateDirectory) {
                Remove-Item -Path $StateDirectory -Recurse -Force
                Write-Verbose "Removed state directory: $StateDirectory"
                $result.StateDirectoryRemoved = $true
            }
            else {
                Write-Verbose 'State directory not found (already removed)'
                $result.StateDirectoryRemoved = $true
            }
        }
        catch {
            Write-Warning "Could not remove state directory: $($_.Exception.Message)"
            $result.StateDirectoryRemoved = $false
        }
    }

    #endregion

    # Determine overall success
    $result.OverallSuccess = $result.ScheduledTaskRemoved -and $result.EventLogSourceRemoved

    return [PSCustomObject]$result
}

# Export the function
Export-ModuleMember -Function 'Uninstall-MakeMeAdminService'
