#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the health of the MakeMeAdminCLI background service.

.DESCRIPTION
    The Test-MakeMeAdminService cmdlet performs a series of diagnostic checks
    on the MakeMeAdminCLI service components and reports their status.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.1.0
#>

function Test-MakeMeAdminService {
    <#
    .SYNOPSIS
        Tests the health of the MakeMeAdminCLI background service.

    .DESCRIPTION
        Performs diagnostic checks on all MakeMeAdminCLI service components
        and returns a status object. This cmdlet does not require elevation
        and can be run by any user to diagnose issues.

        Checks performed:
        - Scheduled task exists
        - Scheduled task is running
        - State directory exists ($env:ProgramData\MakeMeAdminCLI\)
        - config.json exists in the state directory
        - state.json exists in the state directory
        - Windows Event Log source is registered
        - Named pipe (\\.\pipe\MakeMeAdminCLI) is accessible

    .OUTPUTS
        PSCustomObject with boolean properties for each check:
        - TaskExists: Boolean
        - TaskRunning: Boolean
        - StateDirectoryExists: Boolean
        - ConfigFileExists: Boolean
        - StateFileExists: Boolean
        - EventLogSourceExists: Boolean
        - NamedPipeAccessible: Boolean
        - IsHealthy: Boolean (true only if all critical checks pass)

    .EXAMPLE
        Test-MakeMeAdminService

        Runs all diagnostic checks and returns the status object.

    .EXAMPLE
        $health = Test-MakeMeAdminService
        if (-not $health.IsHealthy) {
            Write-Warning "Service is not healthy. Run Install-MakeMeAdminService to fix."
        }

        Programmatically checks service health.

    .EXAMPLE
        Test-MakeMeAdminService | Format-List

        Displays all health check results in list format.

    .LINK
        Install-MakeMeAdminService
        Uninstall-MakeMeAdminService
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # --- Constants ---
    $ModuleName     = 'MakeMeAdminCLI'
    $TaskName       = 'MakeMeAdminCLI-Service'
    $TaskPath       = '\Microsoft\Windows\MakeMeAdminCLI\'
    $EventLogSource = 'MakeMeAdminCLI'
    $PipeName       = 'MakeMeAdminCLI'
    $StateDirectory = Join-Path $env:ProgramData $ModuleName
    $ConfigFilePath = Join-Path $StateDirectory 'config.json'
    $StateFilePath  = Join-Path $StateDirectory 'state.json'

    # --- Check 1: Scheduled task exists ---
    $taskExists = $false
    $taskRunning = $false
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if ($task) {
            $taskExists = $true
            $taskRunning = $task.State -eq 'Running'
            Write-Verbose "Scheduled task found (State: $($task.State))"
        }
        else {
            Write-Verbose 'Scheduled task not found'
        }
    }
    catch {
        Write-Verbose "Error checking scheduled task: $($_.Exception.Message)"
    }

    # --- Check 2: State directory ---
    $stateDirectoryExists = Test-Path $StateDirectory
    Write-Verbose "State directory ($StateDirectory): $(if ($stateDirectoryExists) { 'exists' } else { 'not found' })"

    # --- Check 3: Config file ---
    $configFileExists = Test-Path $ConfigFilePath
    Write-Verbose "Config file ($ConfigFilePath): $(if ($configFileExists) { 'exists' } else { 'not found' })"

    # --- Check 4: State file ---
    $stateFileExists = Test-Path $StateFilePath
    Write-Verbose "State file ($StateFilePath): $(if ($stateFileExists) { 'exists' } else { 'not found' })"

    # --- Check 5: Event Log source ---
    $eventLogSourceExists = $false
    try {
        $eventLogSourceExists = [System.Diagnostics.EventLog]::SourceExists($EventLogSource)
        Write-Verbose "Event Log source '$EventLogSource': $(if ($eventLogSourceExists) { 'registered' } else { 'not found' })"
    }
    catch {
        Write-Verbose "Could not check Event Log source (may require elevation): $($_.Exception.Message)"
    }

    # --- Check 6: Named pipe accessible ---
    $namedPipeAccessible = $false
    $pipeClient = $null
    try {
        $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(
            '.',
            $PipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::None
        )
        $pipeClient.Connect(1000)
        $namedPipeAccessible = $true
        Write-Verbose 'Named pipe is accessible'
    }
    catch {
        Write-Verbose "Named pipe not accessible: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $pipeClient) {
            try { $pipeClient.Dispose() } catch { }
        }
    }

    # --- Determine overall health ---
    # Healthy = task exists + task running + state directory + config + named pipe
    $isHealthy = $taskExists -and $taskRunning -and $stateDirectoryExists -and
                 $configFileExists -and $namedPipeAccessible

    return [PSCustomObject]@{
        TaskExists           = $taskExists
        TaskRunning          = $taskRunning
        StateDirectoryExists = $stateDirectoryExists
        ConfigFileExists     = $configFileExists
        StateFileExists      = $stateFileExists
        EventLogSourceExists = $eventLogSourceExists
        NamedPipeAccessible  = $namedPipeAccessible
        IsHealthy            = $isHealthy
    }
}

# Export the function
Export-ModuleMember -Function 'Test-MakeMeAdminService'
