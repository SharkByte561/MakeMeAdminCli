<#
.SYNOPSIS
    Publishes MakeMeAdminCLI to the PowerShell Gallery.

.DESCRIPTION
    This script validates the module manifest, runs tests, and publishes
    the module to the PowerShell Gallery.

.PARAMETER NuGetApiKey
    Your PowerShell Gallery API key. Get one from https://www.powershellgallery.com/account/apikeys

.PARAMETER WhatIf
    Shows what would happen without actually publishing.

.EXAMPLE
    .\Publish-ToGallery.ps1 -NuGetApiKey "your-api-key-here"

.NOTES
    Before first publish:
    1. Create account at https://www.powershellgallery.com
    2. Generate API key at https://www.powershellgallery.com/account/apikeys
    3. Verify module name "MakeMeAdminCLI" is available
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$NuGetApiKey
)

$ErrorActionPreference = 'Stop'
$ModulePath = Join-Path (Split-Path $PSScriptRoot) 'src\MakeMeAdminCLI'
$ModuleName = 'MakeMeAdminCLI'

Write-Host "=== MakeMeAdminCLI PowerShell Gallery Publisher ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Validate manifest
Write-Host "[1/5] Validating module manifest..." -ForegroundColor Yellow
try {
    $manifest = Test-ModuleManifest -Path "$ModulePath\$ModuleName.psd1" -ErrorAction Stop
    Write-Host "      Module: $($manifest.Name)" -ForegroundColor Green
    Write-Host "      Version: $($manifest.Version)" -ForegroundColor Green
    Write-Host "      Author: $($manifest.Author)" -ForegroundColor Green
}
catch {
    Write-Error "Manifest validation failed: $_"
    exit 1
}

# Step 2: Check required fields for Gallery
Write-Host ""
Write-Host "[2/5] Checking PowerShell Gallery requirements..." -ForegroundColor Yellow

$issues = @()

if ([string]::IsNullOrWhiteSpace($manifest.Description)) {
    $issues += "Description is required"
}
if ([string]::IsNullOrWhiteSpace($manifest.Author)) {
    $issues += "Author is required"
}
if ($null -eq $manifest.Version) {
    $issues += "Version is required"
}

$psData = $manifest.PrivateData.PSData
if ([string]::IsNullOrWhiteSpace($psData.ProjectUri)) {
    $issues += "ProjectUri is recommended (in PrivateData.PSData)"
}
if ([string]::IsNullOrWhiteSpace($psData.LicenseUri)) {
    $issues += "LicenseUri is recommended (in PrivateData.PSData)"
}
if ($null -eq $psData.Tags -or $psData.Tags.Count -eq 0) {
    $issues += "Tags are recommended for discoverability"
}

if ($issues.Count -gt 0) {
    Write-Host "      Issues found:" -ForegroundColor Red
    $issues | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }

    $warnings = $issues | Where-Object { $_ -match "recommended" }
    $errors = $issues | Where-Object { $_ -match "required" }

    if ($errors.Count -gt 0) {
        Write-Error "Required fields are missing. Cannot publish."
        exit 1
    }
}
else {
    Write-Host "      All requirements met" -ForegroundColor Green
}

# Step 3: Check if version already exists
Write-Host ""
Write-Host "[3/5] Checking for existing version on Gallery..." -ForegroundColor Yellow
try {
    $existingModule = Find-Module -Name $ModuleName -ErrorAction SilentlyContinue
    if ($existingModule) {
        if ($existingModule.Version -ge $manifest.Version) {
            Write-Host "      WARNING: Version $($manifest.Version) already exists or is older than $($existingModule.Version)" -ForegroundColor Red
            Write-Host "      Update the version in $ModuleName.psd1 before publishing" -ForegroundColor Red
            exit 1
        }
        Write-Host "      Current Gallery version: $($existingModule.Version)" -ForegroundColor Cyan
        Write-Host "      New version to publish: $($manifest.Version)" -ForegroundColor Green
    }
    else {
        Write-Host "      Module not yet on Gallery (first publish)" -ForegroundColor Green
    }
}
catch {
    Write-Host "      Could not check Gallery (may be first publish)" -ForegroundColor Yellow
}

# Step 4: Run PSScriptAnalyzer if available
Write-Host ""
Write-Host "[4/5] Running static analysis..." -ForegroundColor Yellow
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    $analysisResults = Invoke-ScriptAnalyzer -Path $ModulePath -Recurse -Severity Error, Warning
    if ($analysisResults) {
        Write-Host "      Issues found:" -ForegroundColor Yellow
        $analysisResults | ForEach-Object {
            Write-Host "      [$($_.Severity)] $($_.RuleName): $($_.ScriptName):$($_.Line)" -ForegroundColor Yellow
        }

        $errors = $analysisResults | Where-Object { $_.Severity -eq 'Error' }
        if ($errors) {
            Write-Error "PSScriptAnalyzer found errors. Fix before publishing."
            exit 1
        }
    }
    else {
        Write-Host "      No issues found" -ForegroundColor Green
    }
}
else {
    Write-Host "      PSScriptAnalyzer not installed (skipping)" -ForegroundColor Yellow
    Write-Host "      Install with: Install-Module PSScriptAnalyzer" -ForegroundColor Gray
}

# Step 5: Publish
Write-Host ""
Write-Host "[5/5] Publishing to PowerShell Gallery..." -ForegroundColor Yellow

if ($PSCmdlet.ShouldProcess($ModuleName, "Publish to PowerShell Gallery")) {
    try {
        Publish-Module -Path $ModulePath -NuGetApiKey $NuGetApiKey -Verbose
        Write-Host ""
        Write-Host "SUCCESS! Module published to PowerShell Gallery" -ForegroundColor Green
        Write-Host ""
        Write-Host "View at: https://www.powershellgallery.com/packages/$ModuleName" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Users can now install with:" -ForegroundColor White
        Write-Host "  Install-Module $ModuleName" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Publish failed: $_"
        exit 1
    }
}
else {
    Write-Host "      (WhatIf mode - no changes made)" -ForegroundColor Gray
}
