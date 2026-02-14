<objective>
Add service installation/uninstallation cmdlets to the MakeMeAdminCLI PowerShell module, and add an import-time check that warns users when the background service isn't configured. Today, users must run standalone scripts from the `scripts/` folder to install the service — the goal is to bring that functionality INTO the module itself so PSGallery users can do everything from `Import-Module` + cmdlets without needing the repo's scripts folder.
</objective>

<context>
Read `CLAUDE.md` for project conventions and architecture before making changes.

Key files to examine:
- `src/MakeMeAdminCLI/MakeMeAdminCLI.psm1` — module loader, where import-time logic goes
- `src/MakeMeAdminCLI/MakeMeAdminCLI.psd1` — module manifest, must be updated with new exports
- `scripts/Install-MakeMeAdminCLI.ps1` — current install script (reference implementation for the new cmdlet)
- `scripts/Uninstall-MakeMeAdminCLI.ps1` — current uninstall script (reference implementation)
- `src/MakeMeAdminCLI/Private/Config-Functions.ps1` — config helpers, path constants, existing patterns
- `src/MakeMeAdminCLI/Private/Service-Main.ps1` — the service entrypoint the scheduled task runs
- `src/MakeMeAdminCLI/config.json` — default config shipped with module

Architecture: The "service" is a PowerShell script (`Private/Service-Main.ps1`) running in an infinite loop under Task Scheduler as `NT AUTHORITY\SYSTEM`. It is NOT a Windows Service. The scheduled task name is `MakeMeAdminCLI-Service` under path `\Microsoft\Windows\MakeMeAdminCLI\`.

The module is published to PSGallery. Users install via `Install-Module MakeMeAdminCLI`. After installing the module, they need to run the service setup once from an elevated session. Currently that requires cloning the repo and running install scripts — this work eliminates that gap.
</context>

<requirements>

1. **Import-time service check** (modify `MakeMeAdminCLI.psm1`):
   - At the END of the module loader (after all functions are loaded and exported), add a check for whether the service scheduled task exists
   - Check for the scheduled task `MakeMeAdminCLI-Service` at path `\Microsoft\Windows\MakeMeAdminCLI\`
   - If the task does NOT exist, display a `Write-Warning` message telling the user:
     - The MakeMeAdminCLI service is not installed
     - They need to run `Install-MakeMeAdminService` from an **elevated** PowerShell session to configure it
     - This is a one-time setup step
   - If the task exists but is NOT running, display a `Write-Warning` that the service task exists but isn't running, and suggest they start it or check Task Scheduler
   - The check must be wrapped in try/catch so it never prevents the module from loading (a failed check is a warning, not a fatal error)
   - Do NOT use `Write-Host` — use `Write-Warning` so it respects `-WarningAction` preference

2. **`Install-MakeMeAdminService` cmdlet** (new file `src/MakeMeAdminCLI/Public/Install-MakeMeAdminService.ps1`):
   - Port the logic from `scripts/Install-MakeMeAdminCLI.ps1` into a proper PowerShell advanced function
   - The cmdlet should:
     a. Check if running elevated — if not, write a clear error and return (do NOT use `#Requires -RunAsAdministrator` since that would prevent the module from loading for non-admin users)
     b. Create the `$env:ProgramData\MakeMeAdminCLI\` state directory
     c. Copy `config.json` from the module root to `$env:ProgramData\MakeMeAdminCLI\config.json` (only if it doesn't already exist, or if `-Force` is specified)
     d. Initialize `state.json` in the state directory (only if it doesn't already exist)
     e. Register the Windows Event Log source `MakeMeAdminCLI` (Application log)
     f. Create the scheduled task folder `\Microsoft\Windows\MakeMeAdminCLI\`
     g. Register the scheduled task `MakeMeAdminCLI-Service` that runs `Private\Service-Main.ps1` as SYSTEM at startup with the same settings as the install script
     h. Start the scheduled task
   - Parameters: `-Force` (switch, reinstalls even if already present)
   - Include `[CmdletBinding(SupportsShouldProcess)]` and use `$PSCmdlet.ShouldProcess()` for destructive operations
   - Use the same path constants and patterns as `Config-Functions.ps1` (reference `$script:ModuleRoot`, the `$env:ProgramData\MakeMeAdminCLI` path pattern, etc.)
   - Include full comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
   - Use `Write-Verbose` for progress (not `Write-Host`)
   - Output a summary PSCustomObject at the end with installation status for each component

3. **`Uninstall-MakeMeAdminService` cmdlet** (new file `src/MakeMeAdminCLI/Public/Uninstall-MakeMeAdminService.ps1`):
   - Port the logic from `scripts/Uninstall-MakeMeAdminCLI.ps1` into a proper advanced function
   - The cmdlet should:
     a. Check if running elevated — if not, write a clear error and return
     b. Stop and unregister the scheduled task
     c. Remove the task folder if empty
     d. Optionally remove active elevated users from the Administrators group (only with `-RemoveActiveUsers`)
     e. Remove the Event Log source
     f. Remove the state directory (unless `-KeepConfig` is specified)
   - Parameters: `-KeepConfig` (switch), `-RemoveActiveUsers` (switch), `-Force` (switch, skip confirmation)
   - Do NOT remove the module itself from `Program Files` — that's handled by `Uninstall-Module` and isn't this cmdlet's job
   - Include `[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]` so `-Confirm` works
   - Include full comment-based help
   - Output a summary PSCustomObject with uninstallation status

4. **`Test-MakeMeAdminService` cmdlet** (new file `src/MakeMeAdminCLI/Public/Test-MakeMeAdminService.ps1`):
   - Quick diagnostic function that checks service health (does NOT require elevation)
   - Check and report on:
     a. Whether the scheduled task exists
     b. Whether it's running
     c. Whether `$env:ProgramData\MakeMeAdminCLI\` directory exists
     d. Whether `config.json` and `state.json` exist
     e. Whether the Event Log source is registered
     f. Whether the named pipe `\\.\pipe\MakeMeAdminCLI` is currently accessible
   - Return a PSCustomObject with boolean properties for each check and an overall `IsHealthy` property
   - Include comment-based help

5. **Module manifest and loader updates**:
   - Add the three new functions to `FunctionsToExport` in `MakeMeAdminCLI.psd1`
   - Add the new files to the `FileList` in the manifest
   - Add the new filenames to the `$publicFiles` array in `MakeMeAdminCLI.psm1`
   - Add aliases: `install-mama` for `Install-MakeMeAdminService`, `uninstall-mama` for `Uninstall-MakeMeAdminService`, `test-mama` for `Test-MakeMeAdminService`
   - Export the new aliases in both `.psm1` and `.psd1`

</requirements>

<constraints>
- Do NOT use `#Requires -RunAsAdministrator` on any PUBLIC cmdlet files — the module must load cleanly for non-admin users. Check elevation at runtime and throw a terminating error if not elevated.
- Do NOT use `Write-Host` in cmdlets — use `Write-Verbose` for progress and `Write-Warning` for alerts. The only exception is the import-time check which should use `Write-Warning`.
- Use Windows SIDs (e.g., `S-1-5-32-544`) instead of localized group names, consistent with existing code.
- Follow existing code patterns: comment-based help, approved PowerShell verbs, `$ErrorActionPreference = 'Stop'`, `[CmdletBinding()]`.
- The install cmdlet must determine `Service-Main.ps1`'s path dynamically from the installed module location (use `$PSScriptRoot` or `$MyInvocation` patterns consistent with the existing module).
- The import-time check must be lightweight and non-blocking — it should not slow down `Import-Module` noticeably.
- Do NOT bump the module version — that will be done separately.
</constraints>

<implementation>
Start by reading the existing install and uninstall scripts thoroughly to understand every step. Then:

1. Create `src/MakeMeAdminCLI/Public/Install-MakeMeAdminService.ps1`
2. Create `src/MakeMeAdminCLI/Public/Uninstall-MakeMeAdminService.ps1`
3. Create `src/MakeMeAdminCLI/Public/Test-MakeMeAdminService.ps1`
4. Modify `src/MakeMeAdminCLI/MakeMeAdminCLI.psm1` — add new files to `$publicFiles`, add aliases, add import-time check
5. Modify `src/MakeMeAdminCLI/MakeMeAdminCLI.psd1` — add new functions to exports, add new aliases, add files to FileList

Create a private helper function `Test-IsElevated` in a new file `src/MakeMeAdminCLI/Private/Elevation-Functions.ps1` (and dot-source it in the psm1) so the elevation check is reusable across Install/Uninstall cmdlets. This function should return `$true`/`$false`.
</implementation>

<verification>
After making all changes:

1. Confirm all new `.ps1` files exist under `src/MakeMeAdminCLI/Public/` and `Private/`
2. Confirm `MakeMeAdminCLI.psd1` lists all new functions in `FunctionsToExport`, all new aliases in `AliasesToExport`, and all new files in `FileList`
3. Confirm `MakeMeAdminCLI.psm1` includes new files in `$publicFiles` and `$privateFiles`, defines new aliases, and has the import-time check at the bottom
4. Verify the manifest is valid by running: `Test-ModuleManifest -Path src/MakeMeAdminCLI/MakeMeAdminCLI.psd1`
5. Verify the module loads without errors (even unelevated, should just show warning): `Import-Module ./src/MakeMeAdminCLI/MakeMeAdminCLI.psd1 -Force -Verbose`
6. Verify the new cmdlets appear: `Get-Command -Module MakeMeAdminCLI`
</verification>

<success_criteria>
- `Import-Module MakeMeAdminCLI` shows a warning if the service isn't installed, but loads successfully
- `Install-MakeMeAdminService` (elevated) sets up everything needed for the module to function
- `Uninstall-MakeMeAdminService` (elevated) cleanly tears down the service components
- `Test-MakeMeAdminService` reports health status without requiring elevation
- All existing functionality remains unchanged
- Module manifest passes `Test-ModuleManifest`
</success_criteria>
