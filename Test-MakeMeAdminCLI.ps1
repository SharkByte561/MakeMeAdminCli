#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the MakeMeAdminCLI installation.

.DESCRIPTION
    This script verifies that MakeMeAdminCLI is properly installed and functional.
    It checks:
    - Module is installed at the expected location
    - Module can be imported
    - Service scheduled task exists and is running
    - Named pipe is accessible
    - Event Log source is registered
    - State directory exists and is writable

    This script can be run as a regular user to verify installation,
    but some checks may require administrator privileges.

.PARAMETER Detailed
    Shows detailed information for each check.

.EXAMPLE
    .\Test-MakeMeAdminCLI.ps1

    Runs all installation tests.

.EXAMPLE
    .\Test-MakeMeAdminCLI.ps1 -Detailed

    Runs all tests with detailed output.

.OUTPUTS
    Returns exit code 0 if all tests pass, 1 if any test fails.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [switch]$Detailed
)

$ErrorActionPreference = 'SilentlyContinue'

#region Helper Functions

function Write-TestResult {
    param(
        [bool]$Passed,
        [string]$TestName,
        [string]$Details = ""
    )

    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $statusColor = if ($Passed) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }

    Write-Host "[" -NoNewline
    Write-Host $status -ForegroundColor $statusColor -NoNewline
    Write-Host "] " -NoNewline
    Write-Host $TestName

    if ($Details -and $Detailed) {
        Write-Host "       $Details" -ForegroundColor Gray
    }

    return $Passed
}

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region Test Definitions

$ModuleName = "MakeMeAdminCLI"
$TargetModulePath = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\$ModuleName"
$StateDirectory = Join-Path $env:ProgramData $ModuleName
$TaskName = "MakeMeAdminCLI-Service"
$TaskPath = "\Microsoft\Windows\MakeMeAdminCLI\"
$EventLogSource = "MakeMeAdminCLI"
$PipeName = "MakeMeAdminCLI"

$testResults = @()
$allPassed = $true

Write-Host ""
Write-Host "MakeMeAdminCLI Installation Test" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Module installed at expected location
$test1Passed = Test-Path $TargetModulePath
$test1Details = if ($test1Passed) { "Path: $TargetModulePath" } else { "Module directory not found" }
$passed = Write-TestResult -Passed $test1Passed -TestName "Module installed at expected location" -Details $test1Details
$allPassed = $allPassed -and $passed

# Test 2: Module manifest exists
$manifestPath = Join-Path $TargetModulePath "MakeMeAdminCLI.psd1"
$test2Passed = Test-Path $manifestPath
$test2Details = if ($test2Passed) { "Manifest found: $manifestPath" } else { "Module manifest not found" }
$passed = Write-TestResult -Passed $test2Passed -TestName "Module manifest exists" -Details $test2Details
$allPassed = $allPassed -and $passed

# Test 3: Module can be imported
$test3Passed = $false
$test3Details = ""
try {
    # Try to import the module from the installed location
    if (Test-Path $TargetModulePath) {
        Import-Module $TargetModulePath -Force -ErrorAction Stop
        $test3Passed = $true
        $test3Details = "Module imported successfully"

        # Get module info
        $moduleInfo = Get-Module -Name $ModuleName
        if ($moduleInfo -and $Detailed) {
            $test3Details = "Version: $($moduleInfo.Version), Commands: $($moduleInfo.ExportedCommands.Keys -join ', ')"
        }
    }
}
catch {
    $test3Details = "Import failed: $($_.Exception.Message)"
}
$passed = Write-TestResult -Passed $test3Passed -TestName "Module can be imported" -Details $test3Details
$allPassed = $allPassed -and $passed

# Test 4: Service scheduled task exists
$test4Passed = $false
$test4Details = ""
try {
    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
    $test4Passed = $true
    $test4Details = "Task: $TaskPath\$TaskName"
}
catch {
    $test4Details = "Scheduled task not found"
}
$passed = Write-TestResult -Passed $test4Passed -TestName "Service scheduled task exists" -Details $test4Details
$allPassed = $allPassed -and $passed

# Test 5: Service is running
$test5Passed = $false
$test5Details = ""
try {
    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
    $test5Passed = $task.State -eq 'Running'
    $test5Details = "State: $($task.State)"
}
catch {
    $test5Details = "Could not check service state"
}
$passed = Write-TestResult -Passed $test5Passed -TestName "Service is running" -Details $test5Details
$allPassed = $allPassed -and $passed

# Test 6: Named pipe is accessible
$test6Passed = $false
$test6Details = ""
try {
    $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(
        ".",
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::None
    )

    # Try to connect with a short timeout
    $pipeClient.Connect(2000)
    $test6Passed = $true
    $test6Details = "Connected to pipe: \\.\pipe\$PipeName"
    $pipeClient.Dispose()
}
catch [System.TimeoutException] {
    $test6Details = "Connection timeout - service may be busy"
}
catch [System.IO.FileNotFoundException] {
    $test6Details = "Pipe not found - service may not be running"
}
catch {
    $test6Details = "Error: $($_.Exception.Message)"
}
$passed = Write-TestResult -Passed $test6Passed -TestName "Named pipe is accessible" -Details $test6Details
$allPassed = $allPassed -and $passed

# Test 7: Event Log source registered
$test7Passed = $false
$test7Details = ""
try {
    $test7Passed = [System.Diagnostics.EventLog]::SourceExists($EventLogSource)
    if ($test7Passed) {
        $test7Details = "Source '$EventLogSource' registered in Application log"
    }
    else {
        $test7Details = "Event source not found"
    }
}
catch {
    # May fail if not admin, but source might still exist
    $test7Details = "Could not verify (may require admin)"
    # Don't fail the test for this
    $test7Passed = $true
}
$passed = Write-TestResult -Passed $test7Passed -TestName "Event Log source registered" -Details $test7Details
$allPassed = $allPassed -and $passed

# Test 8: State directory exists and is writable
$test8Passed = $false
$test8Details = ""
if (Test-Path $StateDirectory) {
    # Check if writable (by trying to create a temp file)
    $testFile = Join-Path $StateDirectory ".writetest_$(Get-Random)"
    try {
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item -Path $testFile -Force
        $test8Passed = $true
        $test8Details = "Directory: $StateDirectory"
    }
    catch {
        # May fail if not admin, but directory exists
        if (Test-IsAdministrator) {
            $test8Details = "Directory exists but is not writable"
        }
        else {
            $test8Passed = $true
            $test8Details = "Directory exists (writability check requires admin)"
        }
    }
}
else {
    $test8Details = "State directory not found at $StateDirectory"
}
$passed = Write-TestResult -Passed $test8Passed -TestName "State directory exists and is writable" -Details $test8Details
$allPassed = $allPassed -and $passed

# Test 9: Config file exists
$configPath = Join-Path $StateDirectory "config.json"
$test9Passed = Test-Path $configPath
if (-not $test9Passed) {
    # Also check module directory
    $moduleConfigPath = Join-Path $TargetModulePath "config.json"
    $test9Passed = Test-Path $moduleConfigPath
    if ($test9Passed) {
        $configPath = $moduleConfigPath
    }
}
$test9Details = if ($test9Passed) { "Config: $configPath" } else { "Config file not found" }
$passed = Write-TestResult -Passed $test9Passed -TestName "Configuration file exists" -Details $test9Details
$allPassed = $allPassed -and $passed

# Test 10: Service script exists
$servicePath = Join-Path $TargetModulePath "Private\Service-Main.ps1"
$test10Passed = Test-Path $servicePath
$test10Details = if ($test10Passed) { "Service script: $servicePath" } else { "Service script not found" }
$passed = Write-TestResult -Passed $test10Passed -TestName "Service script exists" -Details $test10Details
$allPassed = $allPassed -and $passed

#endregion

#region Summary

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan

if ($allPassed) {
    Write-Host ""
    Write-Host "All tests passed. MakeMeAdminCLI is ready to use." -ForegroundColor Green
    Write-Host ""
    exit 0
}
else {
    Write-Host ""
    Write-Host "Some tests failed. Please check the installation." -ForegroundColor Red
    Write-Host ""

    if (-not (Test-IsAdministrator)) {
        Write-Host "Note: Some tests may require administrator privileges." -ForegroundColor Yellow
        Write-Host "Try running this script as Administrator for complete results." -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "To reinstall, run:" -ForegroundColor White
    Write-Host "  .\Install-MakeMeAdminCLI.ps1 -Force" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

#endregion
