#Requires -Version 5.1
<#
.SYNOPSIS
    Scheduled task management functions for MakeMeAdminCLI.

.DESCRIPTION
    Provides functions to create, manage, and remove scheduled tasks
    for automatically removing users from the local Administrators group
    after their temporary admin rights expire.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

# Default task settings
$script:DefaultTaskPath = "\Microsoft\Windows\MakeMeAdminCLI"
$script:PowerShellExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

function Ensure-TaskFolderExists {
    <#
    .SYNOPSIS
        Ensures the Task Scheduler folder exists for MakeMeAdminCLI tasks.

    .DESCRIPTION
        Creates the task folder hierarchy if it doesn't exist.
        Uses the COM interface for maximum compatibility.

    .PARAMETER TaskPath
        The task path to create. Defaults to \Microsoft\Windows\MakeMeAdminCLI.
    #>
    [CmdletBinding()]
    param(
        [string]$TaskPath = $script:DefaultTaskPath
    )

    try {
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        $rootFolder = $scheduler.GetFolder("\")

        # Remove leading/trailing backslashes and split
        $relativePath = $TaskPath.Trim("\")
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            return
        }

        $segments = $relativePath -split '\\'
        $currentPath = "\"

        foreach ($segment in $segments) {
            if ([string]::IsNullOrWhiteSpace($segment)) {
                continue
            }

            $nextPath = if ($currentPath -eq "\") { "\$segment" } else { "$currentPath\$segment" }

            try {
                $null = $scheduler.GetFolder($nextPath)
                Write-Verbose "Task folder '$nextPath' already exists."
            }
            catch {
                try {
                    $parentFolder = $scheduler.GetFolder($currentPath)
                    $null = $parentFolder.CreateFolder($segment)
                    Write-Verbose "Created task folder '$nextPath'."
                }
                catch {
                    Write-Warning "Could not create task folder '$nextPath': $($_.Exception.Message)"
                }
            }

            $currentPath = $nextPath
        }
    }
    catch {
        Write-Warning "Error ensuring task folder exists: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $scheduler) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($scheduler) | Out-Null
        }
    }
}

function New-AdminRemovalTask {
    <#
    .SYNOPSIS
        Creates a scheduled task to remove a user from the Administrators group.

    .DESCRIPTION
        Creates a hidden scheduled task that runs as SYSTEM at the specified time
        to remove the user from the local Administrators group. The task includes
        retry logic and self-cleanup.

    .PARAMETER Username
        The username to remove from the Administrators group.

    .PARAMETER ExecuteAt
        The datetime when the removal task should execute.

    .PARAMETER TaskPath
        The path in Task Scheduler where the task will be created.
        Defaults to \Microsoft\Windows\MakeMeAdminCLI.

    .OUTPUTS
        PSCustomObject with TaskName, TaskPath, ExecuteAt, and Success properties.

    .EXAMPLE
        $task = New-AdminRemovalTask -Username "DOMAIN\JohnDoe" -ExecuteAt (Get-Date).AddMinutes(15)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [datetime]$ExecuteAt,

        [string]$TaskPath
    )

    # Get task path from config if not specified
    if (-not $TaskPath) {
        try {
            $configPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config.json"
            if (Test-Path $configPath) {
                $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                $TaskPath = $config.TaskPath
            }
        }
        catch { }
        if (-not $TaskPath) {
            $TaskPath = $script:DefaultTaskPath
        }
    }

    # Generate a unique task name based on the username
    $sanitizedUser = $Username -replace '[\\/:*?"<>|]', '_'
    $taskName = "RemoveAdmin_$sanitizedUser_$(Get-Date -Format 'yyyyMMddHHmmss')"

    $result = [PSCustomObject]@{
        TaskName = $taskName
        TaskPath = $TaskPath
        FullPath = "$TaskPath\$taskName"
        ExecuteAt = $ExecuteAt
        Username = $Username
        Success = $false
        Message = ""
    }

    try {
        # Ensure the task folder exists
        Ensure-TaskFolderExists -TaskPath $TaskPath

        # Build the removal script content
        $removalScript = Build-RemovalScript -Username $Username -TaskName $taskName -TaskPath $TaskPath

        # Create a temporary script file
        $scriptFolder = Join-Path $env:ProgramData "MakeMeAdminCLI\Scripts"
        if (-not (Test-Path $scriptFolder)) {
            New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null
        }
        $scriptPath = Join-Path $scriptFolder "$taskName.ps1"

        if ($PSCmdlet.ShouldProcess($scriptPath, "Create removal script")) {
            Set-Content -Path $scriptPath -Value $removalScript -Encoding UTF8 -Force
        }

        # Create the scheduled task
        if ($PSCmdlet.ShouldProcess($taskName, "Create scheduled task")) {
            $action = New-ScheduledTaskAction -Execute $script:PowerShellExe `
                -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""

            $trigger = New-ScheduledTaskTrigger -Once -At $ExecuteAt

            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount

            $settings = New-ScheduledTaskSettingsSet `
                -StartWhenAvailable `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -Compatibility Win8 `
                -MultipleInstances IgnoreNew `
                -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

            $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings

            Register-ScheduledTask -TaskName $taskName -TaskPath $TaskPath -InputObject $task -Force | Out-Null

            # Try to hide the task (best effort)
            try {
                $taskObj = Get-ScheduledTask -TaskPath $TaskPath -TaskName $taskName -ErrorAction Stop
                if ($taskObj) {
                    $taskObj.Settings.Hidden = $true
                    Set-ScheduledTask -InputObject $taskObj | Out-Null
                    Write-Verbose "Task hidden successfully."
                }
            }
            catch {
                Write-Verbose "Could not set task hidden flag: $($_.Exception.Message)"
            }

            $result.Success = $true
            $result.Message = "Scheduled task '$taskName' created successfully. Removal scheduled for $($ExecuteAt.ToString('yyyy-MM-dd HH:mm:ss'))."
            Write-Verbose $result.Message
        }
    }
    catch {
        $result.Success = $false
        $result.Message = "Failed to create scheduled task: $($_.Exception.Message)"
        Write-Error $result.Message
    }

    return $result
}

function Build-RemovalScript {
    <#
    .SYNOPSIS
        Builds the PowerShell script content for the removal task.

    .DESCRIPTION
        Creates a self-contained PowerShell script that removes a user from
        the Administrators group, includes retry logic, and cleans up after itself.

    .PARAMETER Username
        The username to remove.

    .PARAMETER TaskName
        The name of the scheduled task (for self-cleanup).

    .PARAMETER TaskPath
        The task path (for self-cleanup).

    .OUTPUTS
        String containing the full script content.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath = $script:DefaultTaskPath
    )

    # Get the admin group SID constant
    $adminGroupSID = "S-1-5-32-544"

    $script = @"
#Requires -Version 5.1
# MakeMeAdminCLI - Admin Rights Removal Script
# User: $Username
# Task: $TaskName
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

# Relaunch in 64-bit PowerShell if currently in 32-bit
if (-not [Environment]::Is64BitProcess) {
    `$ps64 = "`$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path `$ps64) {
        & `$ps64 -NoProfile -ExecutionPolicy Bypass -File `$PSCommandPath @args
        exit `$LASTEXITCODE
    }
}

`$ErrorActionPreference = 'Continue'
`$Username = '$Username'
`$TaskName = '$TaskName'
`$TaskPath = '$TaskPath'
`$AdminGroupSID = '$adminGroupSID'
`$EventSource = 'MakeMeAdminCLI'
`$MaxRetries = 3
`$RetryDelaySeconds = 30

# Resolve the Administrators group name from SID
function Get-AdminGroupName {
    try {
        `$sid = New-Object System.Security.Principal.SecurityIdentifier(`$AdminGroupSID)
        `$account = `$sid.Translate([System.Security.Principal.NTAccount])
        `$fullName = `$account.Value
        if (`$fullName -match '\\(.+)`$') {
            return `$Matches[1]
        }
        return `$fullName
    }
    catch {
        return 'Administrators'  # Fallback
    }
}

# Check if user is still a member
function Test-IsMember {
    param([string]`$User, [string]`$Group)
    try {
        `$members = Get-LocalGroupMember -Group `$Group -ErrorAction SilentlyContinue
        foreach (`$member in `$members) {
            if (`$member.Name -eq `$User) { return `$true }
            # Also check just the username part
            if (`$member.Name -match '\\(.+)`$' -and `$User -match '\\(.+)`$') {
                if (`$Matches[1] -eq (`$User -replace '^[^\\]+\\','')) { return `$true }
            }
        }
        return `$false
    }
    catch { return `$false }
}

# Write to event log
function Write-EventLogSafe {
    param([string]`$Message, [int]`$EventId = 1006, [string]`$EntryType = 'Information')
    try {
        `$source = `$EventSource
        if (-not [System.Diagnostics.EventLog]::SourceExists(`$source)) {
            `$source = 'Application'
        }
        Write-EventLog -LogName Application -Source `$source -EventId `$EventId -EntryType `$EntryType -Message `$Message
    }
    catch { }
}

# Main removal logic
`$groupName = Get-AdminGroupName
`$removed = `$false
`$retryCount = 0

while (-not `$removed -and `$retryCount -lt `$MaxRetries) {
    `$retryCount++

    # Check if user is a member before trying to remove
    if (-not (Test-IsMember -User `$Username -Group `$groupName)) {
        `$removed = `$true
        Write-EventLogSafe -Message "User '`$Username' is not a member of '`$groupName'. No removal needed." -EventId 1006
        break
    }

    # Try Remove-LocalGroupMember first
    try {
        Remove-LocalGroupMember -Group `$groupName -Member `$Username -ErrorAction Stop
        Start-Sleep -Milliseconds 500
        if (-not (Test-IsMember -User `$Username -Group `$groupName)) {
            `$removed = `$true
            Write-EventLogSafe -Message "Successfully removed '`$Username' from '`$groupName' (attempt `$retryCount)." -EventId 1006
        }
    }
    catch {
        # Fallback to net localgroup
        try {
            `$null = & net localgroup "`$groupName" "`$Username" /delete 2>&1
            Start-Sleep -Milliseconds 500
            if (-not (Test-IsMember -User `$Username -Group `$groupName)) {
                `$removed = `$true
                Write-EventLogSafe -Message "Successfully removed '`$Username' from '`$groupName' via net localgroup (attempt `$retryCount)." -EventId 1006
            }
        }
        catch { }
    }

    if (-not `$removed -and `$retryCount -lt `$MaxRetries) {
        Start-Sleep -Seconds `$RetryDelaySeconds
    }
}

if (-not `$removed) {
    Write-EventLogSafe -Message "WARNING: Failed to remove '`$Username' from '`$groupName' after `$MaxRetries attempts." -EventId 1010 -EntryType Warning
}

# Update state file
try {
    `$stateFilePath = Join-Path `$env:ProgramData "MakeMeAdminCLI\state.json"
    if (Test-Path `$stateFilePath) {
        `$state = Get-Content -Path `$stateFilePath -Raw | ConvertFrom-Json
        `$updatedUsers = @()
        foreach (`$user in `$state.ActiveUsers) {
            if (`$user.Username -ne `$Username) {
                `$updatedUsers += `$user
            }
        }
        `$state.ActiveUsers = `$updatedUsers
        `$state.LastUpdated = (Get-Date).ToString('o')
        `$state | ConvertTo-Json -Depth 10 | Set-Content -Path `$stateFilePath -Encoding UTF8 -Force
    }
}
catch { }

# Self-cleanup: unregister this task
try {
    Unregister-ScheduledTask -TaskName `$TaskName -TaskPath `$TaskPath -Confirm:`$false -ErrorAction SilentlyContinue
}
catch { }

# Remove this script file
try {
    `$scriptFolder = Join-Path `$env:ProgramData "MakeMeAdminCLI\Scripts"
    `$scriptPath = Join-Path `$scriptFolder "`$TaskName.ps1"
    if (Test-Path `$scriptPath) {
        Remove-Item -Path `$scriptPath -Force -ErrorAction SilentlyContinue
    }
}
catch { }

exit 0
"@

    return $script
}

function Remove-AdminRemovalTask {
    <#
    .SYNOPSIS
        Removes a scheduled admin removal task.

    .DESCRIPTION
        Unregisters a scheduled task and removes its associated script file.

    .PARAMETER TaskName
        The name of the task to remove.

    .PARAMETER TaskPath
        The path of the task. Defaults to \Microsoft\Windows\MakeMeAdminCLI.

    .OUTPUTS
        Boolean indicating success.

    .EXAMPLE
        Remove-AdminRemovalTask -TaskName "RemoveAdmin_DOMAIN_JohnDoe_20240115120000"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath = $script:DefaultTaskPath
    )

    try {
        if ($PSCmdlet.ShouldProcess($TaskName, "Remove scheduled task")) {
            # Remove the scheduled task
            Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue

            # Remove the associated script file
            $scriptFolder = Join-Path $env:ProgramData "MakeMeAdminCLI\Scripts"
            $scriptPath = Join-Path $scriptFolder "$TaskName.ps1"
            if (Test-Path $scriptPath) {
                Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
            }

            Write-Verbose "Task '$TaskName' removed successfully."
            return $true
        }
        return $false
    }
    catch {
        Write-Warning "Failed to remove task '$TaskName': $($_.Exception.Message)"
        return $false
    }
}

function Get-AdminRemovalTasks {
    <#
    .SYNOPSIS
        Gets all pending admin removal tasks.

    .DESCRIPTION
        Returns a list of all scheduled tasks in the MakeMeAdminCLI folder.

    .PARAMETER TaskPath
        The task path to query. Defaults to \Microsoft\Windows\MakeMeAdminCLI.

    .OUTPUTS
        Array of scheduled task objects.

    .EXAMPLE
        $tasks = Get-AdminRemovalTasks
        $tasks | Format-Table TaskName, State, NextRunTime
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$TaskPath = $script:DefaultTaskPath
    )

    try {
        $tasks = Get-ScheduledTask -TaskPath "$TaskPath\" -ErrorAction SilentlyContinue

        $result = @()
        foreach ($task in $tasks) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
            $result += [PSCustomObject]@{
                TaskName = $task.TaskName
                TaskPath = $task.TaskPath
                State = $task.State
                NextRunTime = $taskInfo.NextRunTime
                LastRunTime = $taskInfo.LastRunTime
                LastTaskResult = $taskInfo.LastTaskResult
            }
        }

        return $result
    }
    catch {
        Write-Verbose "Failed to get tasks from '$TaskPath': $($_.Exception.Message)"
        return @()
    }
}

function Remove-AllAdminRemovalTasks {
    <#
    .SYNOPSIS
        Removes all pending admin removal tasks.

    .DESCRIPTION
        Unregisters all scheduled tasks in the MakeMeAdminCLI folder
        and removes their associated script files.

    .PARAMETER TaskPath
        The task path to clean. Defaults to \Microsoft\Windows\MakeMeAdminCLI.

    .EXAMPLE
        Remove-AllAdminRemovalTasks
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$TaskPath = $script:DefaultTaskPath
    )

    $tasks = Get-AdminRemovalTasks -TaskPath $TaskPath

    foreach ($task in $tasks) {
        if ($PSCmdlet.ShouldProcess($task.TaskName, "Remove scheduled task")) {
            Remove-AdminRemovalTask -TaskName $task.TaskName -TaskPath $TaskPath
        }
    }

    # Clean up script folder
    $scriptFolder = Join-Path $env:ProgramData "MakeMeAdminCLI\Scripts"
    if (Test-Path $scriptFolder) {
        if ($PSCmdlet.ShouldProcess($scriptFolder, "Clean up script folder")) {
            Get-ChildItem -Path $scriptFolder -Filter "RemoveAdmin_*.ps1" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

# Export module members (when dot-sourced from module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Ensure-TaskFolderExists',
        'New-AdminRemovalTask',
        'Remove-AdminRemovalTask',
        'Get-AdminRemovalTasks',
        'Remove-AllAdminRemovalTasks'
    )
}
