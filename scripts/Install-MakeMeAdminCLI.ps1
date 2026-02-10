#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the MakeMeAdminCLI module and service.

.DESCRIPTION
    This script performs a complete installation of MakeMeAdminCLI:
    - Copies the module to the system-wide PowerShell modules directory
    - Creates the state directory for tracking active elevated users
    - Registers the Windows Event Log source
    - Creates and starts a scheduled task that runs the service as SYSTEM

    This script must be run as Administrator.

.PARAMETER Force
    Forces installation even if MakeMeAdminCLI is already installed.

.EXAMPLE
    .\Install-MakeMeAdminCLI.ps1

    Performs a standard installation.

.EXAMPLE
    .\Install-MakeMeAdminCLI.ps1 -Force

    Reinstalls MakeMeAdminCLI, overwriting existing files.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0

    Installation paths:
    - Module: $env:ProgramFiles\WindowsPowerShell\Modules\MakeMeAdminCLI\
    - State: $env:ProgramData\MakeMeAdminCLI\
    - Config: $env:ProgramData\MakeMeAdminCLI\config.json
#>

[CmdletBinding()]
param(
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
$ScriptRoot = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptRoot
$ModuleSourcePath = Join-Path $RepoRoot "src\MakeMeAdminCLI"
$ModuleName = "MakeMeAdminCLI"
$TargetModulePath = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\$ModuleName"
$StateDirectory = Join-Path $env:ProgramData $ModuleName
$ConfigFilePath = Join-Path $StateDirectory "config.json"
$TaskName = "MakeMeAdminCLI-Service"
$TaskPath = "\Microsoft\Windows\MakeMeAdminCLI\"
$EventLogSource = "MakeMeAdminCLI"

Write-Host ""
Write-Host "Installing MakeMeAdminCLI..." -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# Check for existing installation
if ((Test-Path $TargetModulePath) -and -not $Force) {
    Write-Status -Status "WARN" -Message "MakeMeAdminCLI is already installed at $TargetModulePath"
    Write-Host ""
    Write-Host "Use -Force to reinstall, or run Uninstall-MakeMeAdminCLI.ps1 first." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# Stop existing service if running
try {
    $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Status -Status "INFO" -Message "Stopping existing service..."
        Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}
catch {
    # Task doesn't exist, continue
}

# Step 1: Copy module to system-wide location
try {
    if (Test-Path $TargetModulePath) {
        Remove-Item -Path $TargetModulePath -Recurse -Force
    }

    # Create the target directory
    New-Item -ItemType Directory -Path $TargetModulePath -Force | Out-Null

    # Copy all module files
    $itemsToCopy = @(
        "MakeMeAdminCLI.psd1",
        "MakeMeAdminCLI.psm1",
        "config.json",
        "ServiceUI.exe",
        "Private",
        "Public"
    )

    foreach ($item in $itemsToCopy) {
        $sourcePath = Join-Path $ModuleSourcePath $item
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $TargetModulePath -Recurse -Force
        }
    }

    Write-Status -Status "OK" -Message "Copied module to $TargetModulePath"
}
catch {
    Write-Status -Status "FAIL" -Message "Failed to copy module: $($_.Exception.Message)"
    exit 1
}

# Step 2: Create state directory
try {
    if (-not (Test-Path $StateDirectory)) {
        New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
    }

    # Copy default config to state directory if it doesn't exist or Force is specified
    $sourceConfig = Join-Path $ModuleSourcePath "config.json"
    if ((Test-Path $sourceConfig) -and (-not (Test-Path $ConfigFilePath) -or $Force)) {
        Copy-Item -Path $sourceConfig -Destination $ConfigFilePath -Force
    }

    # Initialize state file
    $stateFilePath = Join-Path $StateDirectory "state.json"
    if (-not (Test-Path $stateFilePath)) {
        $initialState = @{
            ActiveUsers = @()
            LastUpdated = (Get-Date).ToString('o')
            ServiceStartTime = $null
        }
        $initialState | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFilePath -Encoding UTF8 -Force
    }

    Write-Status -Status "OK" -Message "Created state directory at $StateDirectory"
}
catch {
    Write-Status -Status "FAIL" -Message "Failed to create state directory: $($_.Exception.Message)"
    exit 1
}

# Step 3: Register Event Log source
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
        [System.Diagnostics.EventLog]::CreateEventSource($EventLogSource, "Application")
        Start-Sleep -Milliseconds 500  # Brief pause for registration to complete
    }
    Write-Status -Status "OK" -Message "Registered Event Log source '$EventLogSource'"
}
catch {
    Write-Status -Status "WARN" -Message "Could not register Event Log source: $($_.Exception.Message)"
    # Non-fatal - continue with installation
}

# Step 4: Create scheduled task for the service
try {
    $servicePath = Join-Path $TargetModulePath "Private\Service-Main.ps1"

    # Create the task folder if it doesn't exist
    $taskFolderPath = $TaskPath
    $schedule = New-Object -ComObject Schedule.Service
    $schedule.Connect()
    $rootFolder = $schedule.GetFolder("\")

    try {
        $null = $schedule.GetFolder($taskFolderPath)
    }
    catch {
        # Create the folder hierarchy
        $pathParts = $taskFolderPath.Trim('\').Split('\')
        $currentPath = "\"
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
    }

    # Remove existing task if present
    $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
    }

    # Create the scheduled task
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$servicePath`""

    # Trigger: At system startup
    $trigger = New-ScheduledTaskTrigger -AtStartup

    # Principal: Run as SYSTEM with highest privileges
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    # Settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Days 365) `
        -Priority 4 `
        -Hidden

    # Register the task
    $task = Register-ScheduledTask -TaskName $TaskName `
        -TaskPath $TaskPath `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "MakeMeAdminCLI service - Provides temporary administrator rights to users"

    Write-Status -Status "OK" -Message "Created service scheduled task"
}
catch {
    Write-Status -Status "FAIL" -Message "Failed to create scheduled task: $($_.Exception.Message)"
    exit 1
}

# Step 5: Start the service
try {
    Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath

    # Wait briefly for the service to start
    Start-Sleep -Seconds 2

    $taskInfo = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    if ($taskInfo.State -eq 'Running') {
        Write-Status -Status "OK" -Message "Started MakeMeAdminCLI service"
    }
    else {
        Write-Status -Status "WARN" -Message "Service started but may not be running (State: $($taskInfo.State))"
    }
}
catch {
    Write-Status -Status "WARN" -Message "Could not start service immediately: $($_.Exception.Message)"
    Write-Host "        The service will start automatically on next boot." -ForegroundColor Yellow
}

# Installation complete
Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""
Write-Host "Users can now run:" -ForegroundColor White
Write-Host "  Add-TempAdmin           # Request temporary admin rights" -ForegroundColor Gray
Write-Host "  Get-TempAdminStatus     # Check current status" -ForegroundColor Gray
Write-Host "  Remove-TempAdmin        # Remove admin rights early" -ForegroundColor Gray
Write-Host ""
Write-Host "Configure with: Set-TempAdminConfig (requires elevation)" -ForegroundColor Yellow
Write-Host ""

#endregion
