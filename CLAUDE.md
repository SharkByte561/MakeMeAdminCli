# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MakeMeAdminCLI is a PowerShell module that grants temporary local administrator rights via a client-server architecture. A background service (running as SYSTEM via Task Scheduler) listens on a named pipe; standard users send JSON requests through public cmdlets to add/remove themselves from the local Administrators group with automatic time-based expiration.

## Key Commands

```powershell
# Install (requires Admin PowerShell, run from repo root)
.\scripts\Install-MakeMeAdminCLI.ps1
.\scripts\Install-MakeMeAdminCLI.ps1 -Force   # reinstall

# Uninstall
.\scripts\Uninstall-MakeMeAdminCLI.ps1

# Verify installation (can run as standard user)
.\tests\Test-MakeMeAdminCLI.ps1
.\tests\Test-MakeMeAdminCLI.ps1 -Detailed

# Publish to PSGallery
.\scripts\Publish-ToGallery.ps1
```

There is no build step. The module is pure PowerShell (5.1+). Tests are installation verification checks, not unit tests — they validate the installed service, pipe, event log source, and file paths on a live system.

## Architecture

**Client-server over named pipes (`\\.\pipe\MakeMeAdminCLI`):**

- **Public cmdlets** (user-facing, in `src/MakeMeAdminCLI/Public/`) → call `NamedPipe-Client.ps1` → send JSON over named pipe
- **Service-Main.ps1** (runs as SYSTEM via scheduled task) → receives pipe requests → validates caller identity via `GetImpersonationUserName()` → modifies local Administrators group (SID `S-1-5-32-544`) → creates per-user scheduled removal tasks with retry logic

The service is **not** a Windows Service — it's a PowerShell script running in an infinite loop under Task Scheduler as `NT AUTHORITY\SYSTEM`.

**Security model:** The server gets the client's Windows identity from the pipe connection itself (not from the JSON payload), so users can only elevate themselves. Access control is enforced via `AllowedUsers`/`DeniedUsers` lists in config (deny takes precedence).

**Automatic expiration:** Each elevation creates an independent scheduled task that removes the user at expiry. These tasks survive service crashes and reboots (`-StartWhenAvailable`), with 3 retry attempts.

## Module Structure

The `.psm1` loader dot-sources only `Config-Functions.ps1` and `NamedPipe-Client.ps1` from `Private/` into the client module scope. The remaining Private scripts (`Service-Main.ps1`, `AdminGroup-Functions.ps1`, `ScheduledTask-Functions.ps1`, `Logging-Functions.ps1`) run only in the SYSTEM service context.

Exported functions and their aliases:
- `Add-TempAdmin` (`mama`) — request elevation
- `Remove-TempAdmin` (`rmadmin`) — relinquish elevation
- `Get-TempAdminStatus` (`adminstatus`) — check status
- `Set-TempAdminConfig` — view/modify config (modify requires elevation)

## File Paths at Runtime

| Purpose | Path |
|---------|------|
| Installed module | `C:\Program Files\WindowsPowerShell\Modules\MakeMeAdminCLI\` |
| Runtime config | `C:\ProgramData\MakeMeAdminCLI\config.json` |
| State (active users) | `C:\ProgramData\MakeMeAdminCLI\state.json` |
| Removal scripts | `C:\ProgramData\MakeMeAdminCLI\Scripts\` |

## Code Conventions

- Uses Windows SIDs (e.g., `S-1-5-32-544`) instead of localized group names for language independence
- All public functions use approved PowerShell verbs and include comment-based help
- Diagnostic output uses `Write-Verbose`, not `Write-Host`
- JSON protocol over `StreamReader`/`StreamWriter` for pipe communication
- Event IDs: 1000/1001 (service start/stop), 1005/1006 (grant/remove), 1050 (denied), 1020 (error)
