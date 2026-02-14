@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'MakeMeAdminCLI.psm1'

    # Version number of this module.
    ModuleVersion = '1.2.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'a8e7f3d2-5b4c-4a9e-8f1d-2c3b4a5e6f7d'

    # Author of this module
    Author = 'SharkByte561'

    # Company or vendor of this module
    CompanyName = 'SharkByte561'

    # Copyright statement for this module
    Copyright = '(c) 2025 SharkByte561. MIT License.'

    # Description of the functionality provided by this module
    Description = 'PowerShell module for requesting and managing temporary local administrator rights through a secure named pipe service. Allows non-elevated users to request time-limited admin privileges that are automatically revoked.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Add-TempAdmin',
        'Remove-TempAdmin',
        'Get-TempAdminStatus',
        'Set-TempAdminConfig',
        'Invoke-AsAdmin',
        'Install-MakeMeAdminService',
        'Uninstall-MakeMeAdminService',
        'Test-MakeMeAdminService'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @(
        'mama',
        'rmadmin',
        'adminstatus',
        'runas',
        'install-mama',
        'uninstall-mama',
        'test-mama'
    )

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    FileList = @(
        'MakeMeAdminCLI.psd1',
        'MakeMeAdminCLI.psm1',
        'config.json',
        'ServiceUI.exe',
        'Private\Config-Functions.ps1',
        'Private\NamedPipe-Client.ps1',
        'Private\Logging-Functions.ps1',
        'Private\AdminGroup-Functions.ps1',
        'Private\ScheduledTask-Functions.ps1',
        'Private\Service-Main.ps1',
        'Public\Add-TempAdmin.ps1',
        'Public\Remove-TempAdmin.ps1',
        'Public\Get-TempAdminStatus.ps1',
        'Public\Set-TempAdminConfig.ps1',
        'Public\Invoke-AsAdmin.ps1',
        'Public\Install-MakeMeAdminService.ps1',
        'Public\Uninstall-MakeMeAdminService.ps1',
        'Public\Test-MakeMeAdminService.ps1'
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Admin', 'Administrator', 'Elevation', 'Privilege', 'Security', 'Temporary', 'Windows')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/SharkByte561/MakeMeAdminCLI/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/SharkByte561/MakeMeAdminCLI'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 1.2.0:
- Install-MakeMeAdminService: One-command service setup (scheduled task, config, event log)
- Uninstall-MakeMeAdminService: Clean removal of service and all artifacts
- Test-MakeMeAdminService: Validate service health and configuration
- Import-time service check warns if service is not running

Version 1.1.0:
- Invoke-AsAdmin: Launch elevated programs through SYSTEM service via ServiceUI.exe — no UAC prompt
- Reworked exec flow routes through named pipe to service instead of Start-Process -Verb RunAs
- New Event ID 1060 for process launch auditing
- ServiceUI.exe (Microsoft MDT) bundled for desktop session bridging

Version 1.0.0:
- Initial release
- Add-TempAdmin: Request temporary admin rights
- Remove-TempAdmin: Remove admin rights before expiration
- Get-TempAdminStatus: Check current elevation status
- Set-TempAdminConfig: View and modify configuration
- Named pipe communication with elevated service
- Automatic expiration via scheduled tasks
'@

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}
