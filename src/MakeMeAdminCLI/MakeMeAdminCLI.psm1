#Requires -Version 5.1
<#
.SYNOPSIS
    MakeMeAdminCLI module loader.

.DESCRIPTION
    This is the root module file for MakeMeAdminCLI. It dot-sources all private
    and public function scripts to load them into the module scope.

    The module provides cmdlets for requesting, removing, and managing temporary
    local administrator rights through a named pipe service.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0

    Module Structure:
    - Private/: Helper functions not exported to users
    - Public/: Cmdlets exported to users
#>

$ErrorActionPreference = 'Stop'

# Get the module root directory
$ModuleRoot = $PSScriptRoot

# Set script-scoped variable for use by dot-sourced files
$script:ModuleRoot = $ModuleRoot

# Define paths to function directories
$PrivatePath = Join-Path $ModuleRoot 'Private'
$PublicPath = Join-Path $ModuleRoot 'Public'

#region Load Private Functions

# Private functions are helper functions used internally by the module
# They are not exported to users

$privateFiles = @(
    'Config-Functions.ps1',
    'NamedPipe-Client.ps1'
)

foreach ($file in $privateFiles) {
    $filePath = Join-Path $PrivatePath $file
    if (Test-Path $filePath) {
        try {
            . $filePath
            Write-Verbose "Loaded private function file: $file"
        }
        catch {
            Write-Error "Failed to load private function file '$file': $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "Private function file not found: $filePath"
    }
}

#endregion

#region Load Public Functions

# Public functions are the cmdlets exported to users
# Each file should contain one function matching the file name

$publicFiles = @(
    'Add-TempAdmin.ps1',
    'Remove-TempAdmin.ps1',
    'Get-TempAdminStatus.ps1',
    'Set-TempAdminConfig.ps1',
    'Invoke-AsAdmin.ps1',
    'Install-MakeMeAdminService.ps1',
    'Uninstall-MakeMeAdminService.ps1',
    'Test-MakeMeAdminService.ps1'
)

$functionsToExport = @()

foreach ($file in $publicFiles) {
    $filePath = Join-Path $PublicPath $file
    if (Test-Path $filePath) {
        try {
            . $filePath
            # Extract function name from file name (remove .ps1 extension)
            $functionName = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $functionsToExport += $functionName
            Write-Verbose "Loaded public function file: $file"
        }
        catch {
            Write-Error "Failed to load public function file '$file': $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "Public function file not found: $filePath"
    }
}

#endregion

#region Module Aliases

# Define convenient aliases for common operations
$aliasesToExport = @{
    'mama'           = 'Add-TempAdmin'              # "Make Me Admin" short form
    'rmadmin'        = 'Remove-TempAdmin'            # Remove admin short form
    'adminstatus'    = 'Get-TempAdminStatus'         # Status check
    'runas'          = 'Invoke-AsAdmin'              # Run as admin short form
    'install-mama'   = 'Install-MakeMeAdminService'  # Install service short form
    'uninstall-mama' = 'Uninstall-MakeMeAdminService' # Uninstall service short form
    'test-mama'      = 'Test-MakeMeAdminService'     # Test service short form
}

foreach ($alias in $aliasesToExport.GetEnumerator()) {
    try {
        Set-Alias -Name $alias.Key -Value $alias.Value -Scope Global -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Could not create alias '$($alias.Key)': $($_.Exception.Message)"
    }
}

#endregion

#region Export Module Members

# Export public functions
# Note: The manifest (.psd1) controls what is actually exported,
# but we also export here for direct module import scenarios

Export-ModuleMember -Function @(
    'Add-TempAdmin',
    'Remove-TempAdmin',
    'Get-TempAdminStatus',
    'Set-TempAdminConfig',
    'Invoke-AsAdmin',
    'Install-MakeMeAdminService',
    'Uninstall-MakeMeAdminService',
    'Test-MakeMeAdminService'
)

# Export aliases
Export-ModuleMember -Alias @(
    'mama',
    'rmadmin',
    'adminstatus',
    'runas',
    'install-mama',
    'uninstall-mama',
    'test-mama'
)

#endregion

#region Module Initialization

# Display module load information in verbose mode
Write-Verbose "MakeMeAdminCLI module loaded successfully."
Write-Verbose "Exported functions: $($functionsToExport -join ', ')"
Write-Verbose "Exported aliases: $($aliasesToExport.Keys -join ', ')"

#endregion

#region Import-time Service Check

# Check whether the background service is configured.
# This is a lightweight, non-blocking check that warns users if the service
# is not installed or not running. Wrapped in try/catch so it never prevents
# the module from loading.

try {
    $serviceTaskName = 'MakeMeAdminCLI-Service'
    $serviceTaskPath = '\Microsoft\Windows\MakeMeAdminCLI\'

    $serviceTask = Get-ScheduledTask -TaskName $serviceTaskName -TaskPath $serviceTaskPath -ErrorAction SilentlyContinue

    if (-not $serviceTask) {
        Write-Warning @"
The MakeMeAdminCLI service is not installed.
Run 'Install-MakeMeAdminService' from an elevated PowerShell session to configure it.
This is a one-time setup step.
"@
    }
    elseif ($serviceTask.State -ne 'Running') {
        Write-Warning @"
The MakeMeAdminCLI service task exists but is not running (State: $($serviceTask.State)).
Start it manually or check Task Scheduler: $serviceTaskPath$serviceTaskName
"@
    }
}
catch {
    # Never let the service check prevent module loading
    Write-Verbose "Service check skipped: $($_.Exception.Message)"
}

#endregion
