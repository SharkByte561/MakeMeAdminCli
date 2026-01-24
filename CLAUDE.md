# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MakeMeAdminCLI is a PowerShell module enabling standard Windows users to request temporary local administrator rights via named pipe IPC. It's a CLI-first alternative to the GUI-based MakeMeAdmin application.

**Stack:** PowerShell 5.1+ | Windows Named Pipes | Task Scheduler | Windows Event Log

## Commands

```powershell
# Install (requires Administrator)
.\Install-MakeMeAdminCLI.ps1
.\Install-MakeMeAdminCLI.ps1 -Force    # Reinstall

# Uninstall (requires Administrator)
.\Uninstall-MakeMeAdminCLI.ps1
.\Uninstall-MakeMeAdminCLI.ps1 -KeepConfig

# Run verification tests
.\Test-MakeMeAdminCLI.ps1
.\Test-MakeMeAdminCLI.ps1 -Detailed

# Debug via Event Log
Get-EventLog -LogName Application -Source MakeMeAdminCLI -Newest 20
```

## Architecture

```
User Session (non-elevated)
    │
    ▼
Public Cmdlets (Add-TempAdmin, Remove-TempAdmin, Get-TempAdminStatus)
    │
    ▼
NamedPipe-Client.ps1 ──► Named Pipe: \\.\pipe\MakeMeAdminCLI
                                           │
                                           ▼
                         Service-Main.ps1 (runs as SYSTEM via Scheduled Task)
                              ├── AdminGroup-Functions.ps1
                              ├── ScheduledTask-Functions.ps1
                              ├── Config-Functions.ps1
                              └── Logging-Functions.ps1
```

**Key Design Decisions:**
- Service runs as SYSTEM (required for admin group modification)
- Named pipe provides Windows authentication (client SID verification)
- Users can only elevate themselves (identity verified server-side)
- Automatic expiration via scheduled tasks persists even if service fails
- SID-based admin group operations (language-independent)

## Module Structure

- `Public/` - User-facing cmdlets: `Add-TempAdmin`, `Remove-TempAdmin`, `Get-TempAdminStatus`, `Set-TempAdminConfig`
- `Private/` - Internal functions: pipe server, admin group ops, task scheduling, config, logging
- `MakeMeAdminCLI.psm1` - Module loader (dot-sources Public/ and Private/)
- `MakeMeAdminCLI.psd1` - Module manifest

## IPC Protocol

JSON messages over named pipes:
```json
// Request
{ "action": "add|remove|status", "username": "DOMAIN\\user", "duration": 15 }

// Response
{ "success": true, "message": "...", "expiresAt": "2024-01-15T14:30:00Z" }
```

## Deployment Paths

- Module: `C:\Program Files\WindowsPowerShell\Modules\MakeMeAdminCLI\`
- State/Config: `C:\ProgramData\MakeMeAdminCLI\`

## Event Log IDs

| ID | Level | Purpose |
|----|-------|---------|
| 1005 | Info | Admin rights granted |
| 1006 | Info | Admin rights removed |
| 1050 | Warning | Request denied |
| 1020 | Error | Critical errors |
