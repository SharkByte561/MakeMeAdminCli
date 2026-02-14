#Requires -Version 5.1
<#
.SYNOPSIS
    Tests the Invoke-AsAdmin cmdlet implementation.
#>

$ErrorActionPreference = 'SilentlyContinue'

$ModulePath = Join-Path (Split-Path (Split-Path $PSCommandPath -Parent) -Parent) "src\MakeMeAdminCLI\MakeMeAdminCLI.psd1"
Import-Module $ModulePath -Force -ErrorAction Stop

$passed = 0
$failed = 0

function Write-TestResult {
    param([bool]$Pass, [string]$Name, [string]$Detail = "")
    $status = if ($Pass) { "PASS" } else { "FAIL" }
    $color = if ($Pass) { "Green" } else { "Red" }
    Write-Host "[$status] $Name" -ForegroundColor $color
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor Gray }
    if ($Pass) { $script:passed++ } else { $script:failed++ }
}

Write-Host ""
Write-Host "Invoke-AsAdmin Cmdlet Tests" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Function exists
$cmd = Get-Command Invoke-AsAdmin -ErrorAction SilentlyContinue
Write-TestResult -Pass ($null -ne $cmd) -Name "Invoke-AsAdmin function exists"

# Test 2: Alias exists
$alias = Get-Alias runas -ErrorAction SilentlyContinue
Write-TestResult -Pass ($null -ne $alias -and $alias.ReferencedCommand.Name -eq 'Invoke-AsAdmin') -Name "Alias 'runas' maps to Invoke-AsAdmin"

# Test 3: Has mandatory Program parameter
$programParam = $cmd.Parameters['Program']
Write-TestResult -Pass ($null -ne $programParam) -Name "Has -Program parameter"

# Test 4: Program parameter is mandatory
$isMandatory = $false
foreach ($attr in $programParam.Attributes) {
    if ($attr -is [System.Management.Automation.ParameterAttribute] -and $attr.Mandatory) {
        $isMandatory = $true
    }
}
Write-TestResult -Pass $isMandatory -Name "-Program is mandatory"

# Test 5: Has ArgumentList parameter
$argParam = $cmd.Parameters['ArgumentList']
Write-TestResult -Pass ($null -ne $argParam) -Name "Has -ArgumentList parameter"

# Test 6: Has Wait switch
$waitParam = $cmd.Parameters['Wait']
Write-TestResult -Pass ($null -ne $waitParam -and $waitParam.ParameterType -eq [switch]) -Name "Has -Wait switch parameter"

# Test 7: Has WorkingDirectory parameter
$wdParam = $cmd.Parameters['WorkingDirectory']
Write-TestResult -Pass ($null -ne $wdParam) -Name "Has -WorkingDirectory parameter"

# Test 8: SupportsShouldProcess (WhatIf available)
$whatif = $cmd.Parameters['WhatIf']
Write-TestResult -Pass ($null -ne $whatif) -Name "Supports -WhatIf (SupportsShouldProcess)"

# Test 9: WhatIf mode - does not return a process (no actual launch)
$result = Invoke-AsAdmin notepad -WhatIf -WarningAction SilentlyContinue
Write-TestResult -Pass ($null -eq $result) -Name "-WhatIf prevents actual launch (returns null)"

# Test 10: Non-existent program produces error
$hasError = $false
try {
    Invoke-AsAdmin "ZZZ_nonexistent_program_ZZZ" -ErrorAction Stop 2>$null
}
catch {
    $hasError = $true
}
Write-TestResult -Pass $hasError -Name "Non-existent program produces error"

# Test 11: Help is available
$help = Get-Help Invoke-AsAdmin -Full 2>$null
$hasSynopsis = $help.Synopsis -match 'Launches.*application.*elevated'
Write-TestResult -Pass $hasSynopsis -Name "Comment-based help is available" -Detail "Synopsis: $($help.Synopsis.Trim())"

# Test 12: Has examples in help
$exampleCount = @($help.Examples.Example).Count
Write-TestResult -Pass ($exampleCount -ge 3) -Name "Has at least 3 help examples" -Detail "Found $exampleCount examples"

# Summary
Write-Host ""
Write-Host "===========================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($failed -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
}
