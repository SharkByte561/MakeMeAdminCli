<objective>
Add a new public cmdlet `Invoke-AsAdmin` (alias: `runas`) to the MakeMeAdminCLI PowerShell module. This cmdlet launches an application with elevation using `Start-Process -Verb RunAs` after the user has added themselves to the local Administrators group via `Add-TempAdmin`.

When a user runs `Add-TempAdmin`, they are added to the local Administrators group — but their current session token is unchanged. `Start-Process -Verb RunAs` triggers a UAC consent prompt (just click Yes, no password required) because the user is now a member of the Administrators group. This cmdlet wraps that pattern into a convenient, discoverable command.
</objective>

<context>
Read the project's CLAUDE.md for architecture and conventions before starting.

This is a PowerShell 5.1+ module using a client-server architecture:
- Public cmdlets live in `./src/MakeMeAdminCLI/Public/` (one function per file)
- Private helper functions live in `./src/MakeMeAdminCLI/Private/`
- The module loader is `./src/MakeMeAdminCLI/MakeMeAdminCLI.psm1` — it dot-sources Private and Public scripts
- The module manifest is `./src/MakeMeAdminCLI/MakeMeAdminCLI.psd1` — it declares exported functions and aliases
- Public cmdlets communicate with the SYSTEM service via named pipe using `NamedPipe-Client.ps1`

Read these files to understand existing patterns before implementing:
- `./src/MakeMeAdminCLI/Public/Add-TempAdmin.ps1` — primary example of a public cmdlet
- `./src/MakeMeAdminCLI/Public/Get-TempAdminStatus.ps1` — shows how to check elevation status
- `./src/MakeMeAdminCLI/MakeMeAdminCLI.psm1` — module loader, must be updated
- `./src/MakeMeAdminCLI/MakeMeAdminCLI.psd1` — manifest, must be updated
</context>

<requirements>
1. Create `./src/MakeMeAdminCLI/Public/Invoke-AsAdmin.ps1` containing the `Invoke-AsAdmin` function
2. The cmdlet must:
   a. Accept a mandatory `-Program` parameter (string) — the executable name or path to launch
   b. Accept an optional `-ArgumentList` parameter (string[]) — arguments to pass to the program
   c. Accept an optional `-Wait` switch — if specified, wait for the launched process to exit
   d. Accept an optional `-WorkingDirectory` parameter (string) — set the working directory for the launched process
   e. Before launching, check if the current user is in the local Administrators group (by querying the service via named pipe with a `status` action, or by checking group membership directly). If NOT elevated, warn the user and suggest running `Add-TempAdmin` first — but still allow the launch attempt (the UAC prompt would then ask for credentials, which is standard Windows behavior)
   f. Use `Start-Process -Verb RunAs` to launch the program, which triggers a UAC consent prompt (no password needed when user is already an admin)
   g. If `-Program` is not a full path, resolve it from PATH so the user can type things like `Invoke-AsAdmin powershell` or `Invoke-AsAdmin notepad`
   h. Return the Process object when `-Wait` is not specified, or the exit code when `-Wait` is specified
   i. Include proper error handling for: program not found, user cancelled UAC prompt, launch failure

3. Register the alias `runas` for `Invoke-AsAdmin`

4. Update `./src/MakeMeAdminCLI/MakeMeAdminCLI.psm1`:
   - Add `Invoke-AsAdmin.ps1` to the `$publicFiles` array
   - Add the `runas` alias to the `$aliasesToExport` hashtable
   - Add `Invoke-AsAdmin` to the `Export-ModuleMember -Function` call
   - Add `runas` to the `Export-ModuleMember -Alias` call

5. Update `./src/MakeMeAdminCLI/MakeMeAdminCLI.psd1`:
   - Add `Invoke-AsAdmin` to `FunctionsToExport`
   - Add `runas` to `AliasesToExport`
   - Add `Public\Invoke-AsAdmin.ps1` to `FileList`
</requirements>

<implementation>
Follow the exact patterns established by the existing public cmdlets:
- Use `[CmdletBinding()]` and `param()` block
- Include full comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`)
- Use `Write-Verbose` for diagnostic output, never `Write-Host` for non-essential output
- Use `Write-Warning` when the user is not currently elevated (to suggest `Add-TempAdmin`)
- Use `SupportsShouldProcess` since this cmdlet launches external processes

For checking admin group membership locally (without going through the named pipe), use the SID-based approach the module already uses for language independence:
```powershell
$adminSID = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
```

For resolving program names from PATH, use `Get-Command` with `-ErrorAction SilentlyContinue` to find the executable.

Do NOT create any new Private helper files — this cmdlet can be self-contained using `Start-Process`.
</implementation>

<output>
Create or modify these files:
- `./src/MakeMeAdminCLI/Public/Invoke-AsAdmin.ps1` — NEW: the cmdlet implementation
- `./src/MakeMeAdminCLI/MakeMeAdminCLI.psm1` — MODIFY: register the new function and alias
- `./src/MakeMeAdminCLI/MakeMeAdminCLI.psd1` — MODIFY: export the new function and alias
</output>

<verification>
After implementation, verify:
1. The new file `./src/MakeMeAdminCLI/Public/Invoke-AsAdmin.ps1` exists and contains the function
2. The `.psm1` references the new file in `$publicFiles`, the alias in `$aliasesToExport`, and both in `Export-ModuleMember`
3. The `.psd1` includes the function in `FunctionsToExport`, alias in `AliasesToExport`, and file in `FileList`
4. The function includes comment-based help with at least 3 examples:
   - `Invoke-AsAdmin powershell` — launch elevated PowerShell
   - `Invoke-AsAdmin cmd.exe` — launch elevated Command Prompt
   - `Invoke-AsAdmin notepad "C:\Windows\System32\drivers\etc\hosts"` — launch with arguments
</verification>

<success_criteria>
- `Invoke-AsAdmin` function is implemented following the same patterns as existing cmdlets
- Alias `runas` is registered
- Module loader and manifest are updated consistently
- User gets a warning (not an error) when not yet elevated
- `Start-Process -Verb RunAs` is used for the actual elevation
- Program resolution from PATH works for common executables
- Comment-based help is complete and accurate
</success_criteria>
