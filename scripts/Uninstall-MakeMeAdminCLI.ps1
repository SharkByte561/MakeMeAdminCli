#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls the MakeMeAdminCLI module and service.

.DESCRIPTION
    This script performs a complete uninstallation of MakeMeAdminCLI:
    - Stops and removes the scheduled task service
    - Optionally removes active elevated users from the Administrators group
    - Removes the Windows Event Log source
    - Removes the state directory (unless -KeepConfig is specified)
    - Removes the module from the system-wide PowerShell modules directory

    This script must be run as Administrator.

.PARAMETER KeepConfig
    If specified, keeps the configuration and state files in ProgramData.
    Useful for reinstallation scenarios.

.PARAMETER Force
    Skips confirmation prompts for removing active users.

.EXAMPLE
    .\Uninstall-MakeMeAdminCLI.ps1

    Performs a standard uninstallation with prompts.

.EXAMPLE
    .\Uninstall-MakeMeAdminCLI.ps1 -KeepConfig

    Uninstalls but keeps the configuration for future reinstallation.

.EXAMPLE
    .\Uninstall-MakeMeAdminCLI.ps1 -Force

    Uninstalls without prompting for confirmation.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [switch]$KeepConfig,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

#region Helper Functions

function Write-Status {
    param(
        [string]$Status,
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    $statusColor = switch ($Status) {
        'OK' { [ConsoleColor]::Green }
        'WARN' { [ConsoleColor]::Yellow }
        'FAIL' { [ConsoleColor]::Red }
        'INFO' { [ConsoleColor]::Cyan }
        'SKIP' { [ConsoleColor]::DarkGray }
        default { [ConsoleColor]::White }
    }

    Write-Host "[" -NoNewline
    Write-Host $Status -ForegroundColor $statusColor -NoNewline
    Write-Host "] " -NoNewline
    Write-Host $Message -ForegroundColor $Color
}

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ActiveElevatedUsers {
    param(
        [string]$StateFilePath
    )

    if (-not (Test-Path $StateFilePath)) {
        return @()
    }

    try {
        $state = Get-Content -Path $StateFilePath -Raw | ConvertFrom-Json
        if ($state.ActiveUsers) {
            return @($state.ActiveUsers)
        }
    }
    catch {
        Write-Verbose "Could not read state file: $($_.Exception.Message)"
    }

    return @()
}

function Remove-UserFromAdministrators {
    param(
        [string]$Username
    )

    try {
        # Get the local Administrators group by SID (language-independent)
        $adminGroupSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $adminGroup = $adminGroupSid.Translate([System.Security.Principal.NTAccount]).Value
        $localAdminGroup = [ADSI]"WinNT://./$($adminGroup.Split('\')[-1]),group"

        # Find and remove the user
        $members = @($localAdminGroup.Invoke("Members") | ForEach-Object {
            $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
        })

        $usernameShort = $Username -replace '^[^\\]+\\', ''

        if ($members -contains $usernameShort) {
            $localAdminGroup.Remove("WinNT://$Username")
            return @{ Success = $true; Message = "Removed from Administrators group" }
        }
        else {
            return @{ Success = $true; Message = "Not currently a member" }
        }
    }
    catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

#endregion

#region Main Script

# Verify running as Administrator
if (-not (Test-IsAdministrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Define paths
$ModuleName = "MakeMeAdminCLI"
$TargetModulePath = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\$ModuleName"
$StateDirectory = Join-Path $env:ProgramData $ModuleName
$StateFilePath = Join-Path $StateDirectory "state.json"
$TaskName = "MakeMeAdminCLI-Service"
$TaskPath = "\Microsoft\Windows\MakeMeAdminCLI\"
$EventLogSource = "MakeMeAdminCLI"

Write-Host ""
Write-Host "Uninstalling MakeMeAdminCLI..." -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Confirm uninstallation
if (-not $Force) {
    $response = Read-Host "Are you sure you want to uninstall MakeMeAdminCLI? (Y/N)"
    if ($response -notin @('Y', 'y', 'Yes', 'yes')) {
        Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

# Step 1: Stop and remove the scheduled task
try {
    $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue

    if ($existingTask) {
        # Stop the task if running
        if ($existingTask.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        # Unregister the task
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false

        # Try to remove the task folder (if empty)
        try {
            $schedule = New-Object -ComObject Schedule.Service
            $schedule.Connect()
            $folder = $schedule.GetFolder($TaskPath)
            $tasks = $folder.GetTasks(0)
            if ($tasks.Count -eq 0) {
                $parentPath = Split-Path $TaskPath -Parent
                if ($parentPath -eq '\') { $parentPath = '\' }
                $parentFolder = $schedule.GetFolder($parentPath)
                $folderName = Split-Path $TaskPath -Leaf
                $parentFolder.DeleteFolder($folderName, 0)
            }
        }
        catch {
            # Ignore errors removing the folder
        }

        Write-Status -Status "OK" -Message "Stopped and removed scheduled task"
    }
    else {
        Write-Status -Status "SKIP" -Message "Scheduled task not found"
    }
}
catch {
    Write-Status -Status "WARN" -Message "Could not remove scheduled task: $($_.Exception.Message)"
}

# Step 2: Remove active elevated users from Administrators group
try {
    $activeUsers = Get-ActiveElevatedUsers -StateFilePath $StateFilePath

    if ($activeUsers.Count -gt 0) {
        Write-Host ""
        Write-Host "Found $($activeUsers.Count) active elevated user(s):" -ForegroundColor Yellow

        foreach ($user in $activeUsers) {
            Write-Host "  - $($user.Username) (expires: $($user.ExpiresAt))" -ForegroundColor Gray
        }

        Write-Host ""

        $removeUsers = $true
        if (-not $Force) {
            $response = Read-Host "Remove these users from the Administrators group? (Y/N)"
            $removeUsers = $response -in @('Y', 'y', 'Yes', 'yes')
        }

        if ($removeUsers) {
            foreach ($user in $activeUsers) {
                $result = Remove-UserFromAdministrators -Username $user.Username
                if ($result.Success) {
                    Write-Status -Status "OK" -Message "Removed '$($user.Username)' from Administrators"
                }
                else {
                    Write-Status -Status "WARN" -Message "Could not remove '$($user.Username)': $($result.Message)"
                }
            }
        }
        else {
            Write-Status -Status "SKIP" -Message "Keeping elevated users in Administrators group"
        }
    }
    else {
        Write-Status -Status "OK" -Message "No active elevated users to remove"
    }
}
catch {
    Write-Status -Status "WARN" -Message "Could not check active users: $($_.Exception.Message)"
}

# Step 3: Remove Event Log source
try {
    if ([System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
        [System.Diagnostics.EventLog]::DeleteEventSource($EventLogSource)
        Write-Status -Status "OK" -Message "Removed Event Log source '$EventLogSource'"
    }
    else {
        Write-Status -Status "SKIP" -Message "Event Log source not found"
    }
}
catch {
    Write-Status -Status "WARN" -Message "Could not remove Event Log source: $($_.Exception.Message)"
}

# Step 4: Remove state directory
if ($KeepConfig) {
    Write-Status -Status "SKIP" -Message "Keeping configuration at $StateDirectory"
}
else {
    try {
        if (Test-Path $StateDirectory) {
            Remove-Item -Path $StateDirectory -Recurse -Force
            Write-Status -Status "OK" -Message "Removed state directory at $StateDirectory"
        }
        else {
            Write-Status -Status "SKIP" -Message "State directory not found"
        }
    }
    catch {
        Write-Status -Status "WARN" -Message "Could not remove state directory: $($_.Exception.Message)"
    }
}

# Step 5: Remove module from Program Files
try {
    if (Test-Path $TargetModulePath) {
        Remove-Item -Path $TargetModulePath -Recurse -Force
        Write-Status -Status "OK" -Message "Removed module from $TargetModulePath"
    }
    else {
        Write-Status -Status "SKIP" -Message "Module not found at $TargetModulePath"
    }
}
catch {
    Write-Status -Status "WARN" -Message "Could not remove module: $($_.Exception.Message)"
}

# Uninstallation complete
Write-Host ""
Write-Host "Uninstallation complete." -ForegroundColor Green
Write-Host ""

if ($KeepConfig) {
    Write-Host "Configuration files were preserved at: $StateDirectory" -ForegroundColor Yellow
    Write-Host "To reinstall, run Install-MakeMeAdminCLI.ps1" -ForegroundColor Gray
}

Write-Host ""

#endregion
