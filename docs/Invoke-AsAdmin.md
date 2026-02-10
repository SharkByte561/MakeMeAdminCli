# Invoke-AsAdmin — Technical Overview

## The Problem

When `Add-TempAdmin` adds a user to the local Administrators group mid-session, Windows does **not** update the user's existing logon token. UAC creates tokens at logon time, so `Start-Process -Verb RunAs` still presents a **credential prompt** (asking for an admin password) instead of the expected consent prompt (just click Yes). This made the original implementation impractical.

## The Solution

Route process launching through the SYSTEM service using **ServiceUI.exe**, a legitimate Microsoft tool from the MDT (Microsoft Deployment Toolkit). The SYSTEM service launches the process directly, and ServiceUI.exe bridges it to the user's interactive desktop session. No UAC prompt at all.

## How It Works

```
User Shell                        SYSTEM Service (Task Scheduler)
-----------                       --------------------------------
Invoke-AsAdmin notepad
  |
  +--> Resolve "notepad" to
       C:\Windows\system32\notepad.exe
  |
  +--> Send JSON over named pipe:
       { "action": "exec",
         "program": "C:\\Windows\\system32\\notepad.exe" }
            |
            +----> Named Pipe (\\.\pipe\MakeMeAdminCLI)
                        |
                        v
                   Invoke-ExecRequest
                     |
                     +--> Verify caller has active mama session
                     |    (checks state.json via Get-ActiveUsers)
                     |
                     +--> Validate program path exists on disk
                     |
                     +--> Locate ServiceUI.exe in module root
                     |
                     +--> Start-Process ServiceUI.exe
                     |      -process:explorer.exe "notepad.exe"
                     |
                     +--> Log Event ID 1060
                     |
                     +--> Return { success: true }
                            |
                            v
                   ServiceUI.exe finds the desktop session
                   where explorer.exe is running (the user's
                   interactive session) and launches notepad.exe
                   in that session context.
                            |
                            v
                   Notepad appears on the user's desktop,
                   running elevated. No UAC prompt.
```

## Why ServiceUI.exe?

The SYSTEM service runs in Session 0 (a non-interactive session). Processes started from Session 0 are invisible to the logged-in user. ServiceUI.exe solves this by:

1. Finding the session where `explorer.exe` is running (the user's interactive desktop)
2. Launching the target process in that session
3. The process inherits SYSTEM-level elevation

This is the same technique used by SCCM/MDT task sequences to show UI during OS deployments.

## Security Model

| Check | Where | Detail |
|-------|-------|--------|
| Identity verification | Named pipe impersonation | `GetImpersonationUserName()` gets the real caller — cannot be spoofed via JSON |
| Active elevation required | `Invoke-ExecRequest` | Caller must have an active `mama` session in `state.json` |
| AllowedUsers/DeniedUsers | Enforced at `Add-TempAdmin` time | If you couldn't get `mama`, you can't `exec` |
| Program path validation | `Invoke-ExecRequest` | `Test-Path` confirms the executable exists before launch |
| Audit trail | Event Log | Event ID 1060 logged for every exec with username + program path |

A user cannot use `Invoke-AsAdmin` without first passing all the access control checks during `Add-TempAdmin`. The `exec` handler is gated on having an active entry in the state file.

## Parameters

### -Program (Required, Position 0)

The executable name or full path.

```powershell
# Resolved from PATH automatically
Invoke-AsAdmin powershell
Invoke-AsAdmin cmd.exe
Invoke-AsAdmin notepad

# Full path
Invoke-AsAdmin "X:\Vault\Tools\VeraCrypt\VeraCrypt-x64.exe"
Invoke-AsAdmin "C:\Program Files\7-Zip\7zFM.exe"
```

If the name is not a rooted path, the cmdlet resolves it via `Get-Command -CommandType Application` before sending to the service. The service receives and validates the full path.

### -ArgumentList (Optional, Position 1, ValueFromRemainingArguments)

Arguments passed to the target program. Because `ValueFromRemainingArguments` is set, everything after the program name is captured as arguments.

```powershell
# Positional — everything after the program name becomes arguments
Invoke-AsAdmin notepad "C:\Windows\System32\drivers\etc\hosts"

# Named parameter with array
Invoke-AsAdmin -Program powershell -ArgumentList '-NoProfile', '-Command', 'Get-Service'

# MMC snap-ins (.msc files)
Invoke-AsAdmin mmc.exe diskmgmt.msc
Invoke-AsAdmin mmc.exe devmgmt.msc
Invoke-AsAdmin mmc.exe compmgmt.msc
```

### -WorkingDirectory (Optional)

Sets the working directory for the launched process.

```powershell
Invoke-AsAdmin cmd.exe -WorkingDirectory "C:\Projects"
Invoke-AsAdmin powershell -WorkingDirectory "$env:USERPROFILE\Desktop"
```

The directory must exist; the cmdlet validates this before sending the request.

### -WhatIf / -Confirm (SupportsShouldProcess)

Standard PowerShell safety parameters.

```powershell
# Preview without executing
Invoke-AsAdmin notepad -WhatIf

# Prompt for confirmation
Invoke-AsAdmin cmd.exe -Confirm
```

## Output

Returns a `PSCustomObject` with two properties:

| Property | Type | Description |
|----------|------|-------------|
| `Success` | `bool` | Whether the process was launched |
| `Message` | `string` | Result detail or error reason |

```powershell
$result = Invoke-AsAdmin notepad
if ($result.Success) {
    Write-Host "Launched"
}
```

## Alias

`runas` is aliased to `Invoke-AsAdmin`:

```powershell
runas notepad
runas mmc.exe diskmgmt.msc
```

## Common Patterns

```powershell
# Full workflow: elevate then launch
mama                              # Add-TempAdmin alias
runas powershell                  # Elevated PowerShell
runas regedit                     # Registry Editor
runas mmc.exe services.msc       # Services snap-in
runas mmc.exe diskmgmt.msc       # Disk Management
rmadmin                           # Remove-TempAdmin when done

# Check if you can exec before trying
$status = adminstatus
if ($status.isAdmin) {
    Invoke-AsAdmin cmd.exe
} else {
    Write-Host "Run mama first"
}
```

## Event Log

All exec actions are logged to the Application event log under source `MakeMeAdminCLI`:

| Event ID | Level | Description |
|----------|-------|-------------|
| 1040 | Information | Request received (action: exec) |
| 1050 | Warning | Request denied (no active session) |
| 1060 | Information | Process launched (username + program path) |
| 1020 | Error | Launch failure |

Query with:
```powershell
Get-EventLog -LogName Application -Source MakeMeAdminCLI | Where-Object EventID -eq 1060
```

## Limitations

- **No -Wait**: ServiceUI.exe launches asynchronously. The client cannot wait for the process to exit through the pipe + ServiceUI chain.
- **No process object returned**: Returns a success/failure object, not a `System.Diagnostics.Process`.
- **Single interactive session**: ServiceUI.exe targets the session running `explorer.exe`. If multiple users are logged in, it targets the first match.
