# MakeMeAdminCLI Technical Architecture

This document provides a deep technical explanation of how MakeMeAdminCLI implements secure temporary privilege elevation using Windows Named Pipes and Task Scheduler.

## Table of Contents
- [Overview](#overview)
- [Why Not a Windows Service?](#why-not-a-windows-service)
- [Named Pipe IPC Protocol](#named-pipe-ipc-protocol)
- [Security Model](#security-model)
- [Automatic Expiration System](#automatic-expiration-system)
- [State Management](#state-management)

---

## Overview

MakeMeAdminCLI uses a client-server architecture where:
- **Server**: A PowerShell script (`Service-Main.ps1`) runs as SYSTEM via Task Scheduler
- **Client**: Public cmdlets communicate with the server via named pipes
- **Expiration**: Separate scheduled tasks ensure admin rights are removed even if the service crashes

```
┌─────────────────────────────────────────────────────────────────────┐
│                    USER SESSION (non-elevated)                      │
│                                                                     │
│   Add-TempAdmin ──► NamedPipe-Client.ps1 ──► JSON Request          │
│                                                   │                 │
└───────────────────────────────────────────────────┼─────────────────┘
                                                    │
                                    \\.\pipe\MakeMeAdminCLI
                                                    │
┌───────────────────────────────────────────────────┼─────────────────┐
│                    SYSTEM CONTEXT                 │                 │
│                                                   ▼                 │
│   ┌──────────────────────────────────────────────────────┐         │
│   │              Service-Main.ps1                         │         │
│   │  - Listens on named pipe                              │         │
│   │  - Validates client identity via impersonation        │         │
│   │  - Adds/removes users from Administrators group       │         │
│   │  - Creates scheduled removal tasks                    │         │
│   └──────────────────────────────────────────────────────┘         │
│                      │                    │                         │
│                      ▼                    ▼                         │
│              Local Admins          Task Scheduler                   │
│              S-1-5-32-544         (Removal Tasks)                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Why Not a Windows Service?

Traditional Windows Services require compiled binaries (`.exe`) with specific service control interfaces. MakeMeAdminCLI uses **Task Scheduler** instead for several reasons:

| Aspect | Windows Service | Task Scheduler (Our Approach) |
|--------|-----------------|-------------------------------|
| **Implementation** | Requires compiled binary | Pure PowerShell |
| **Installation** | `sc.exe create` / `New-Service` | `Register-ScheduledTask` |
| **Runs as SYSTEM** | Yes | Yes |
| **Auto-restart** | Via service recovery options | Via task settings |
| **Deployment complexity** | Higher (signing, install scripts) | Lower (just copy files) |

### How the "Service" Works

The installer creates a scheduled task that:
1. Triggers **at system startup**
2. Runs as **NT AUTHORITY\SYSTEM**
3. Executes `Service-Main.ps1` which runs an **infinite loop**
4. Listens for client connections on the named pipe

```powershell
# From Install-MakeMeAdminCLI.ps1
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ServiceScript`""

$principal = New-ScheduledTaskPrincipal `
    -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest
```

---

## Named Pipe IPC Protocol

### Why Named Pipes?

Named pipes provide several advantages for local IPC:
1. **Built-in Windows authentication** - The OS handles identity verification
2. **No network exposure** - Local pipes (`\\.\pipe\`) cannot be accessed remotely
3. **Access control via ACLs** - Fine-grained permissions on who can connect
4. **Message-oriented** - Natural fit for request/response patterns

### Pipe Configuration

```powershell
# Server creates pipe with specific security
$pipeSecurity = New-Object System.IO.Pipes.PipeSecurity

# SYSTEM gets full control
$pipeSecurity.AddAccessRule(
    [System.Security.Principal.SecurityIdentifier]::new("S-1-5-18"),  # SYSTEM
    [System.IO.Pipes.PipeAccessRights]::FullControl,
    [System.Security.AccessControl.AccessControlType]::Allow
)

# Administrators get full control
$pipeSecurity.AddAccessRule(
    [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544"),  # Administrators
    [System.IO.Pipes.PipeAccessRights]::FullControl,
    [System.Security.AccessControl.AccessControlType]::Allow
)

# Authenticated Users can read/write (connect and send requests)
$pipeSecurity.AddAccessRule(
    [System.Security.Principal.SecurityIdentifier]::new("S-1-5-11"),  # Authenticated Users
    [System.IO.Pipes.PipeAccessRights]::ReadWrite,
    [System.Security.AccessControl.AccessControlType]::Allow
)

$pipe = New-Object System.IO.Pipes.NamedPipeServerStream(
    "MakeMeAdminCLI",                                    # Pipe name
    [System.IO.Pipes.PipeDirection]::InOut,              # Bidirectional
    1,                                                    # Max 1 instance
    [System.IO.Pipes.PipeTransmissionMode]::Message,     # Message mode
    [System.IO.Pipes.PipeOptions]::Asynchronous,         # Async operations
    4096,                                                 # In buffer
    4096,                                                 # Out buffer
    $pipeSecurity                                         # Security descriptor
)
```

### Protocol Format

All communication uses JSON over StreamReader/StreamWriter:

**Request:**
```json
{
    "action": "add",
    "username": "CONTOSO\\jsmith",
    "duration": 30
}
```

**Response:**
```json
{
    "success": true,
    "message": "Temporary admin rights granted for 30 minutes",
    "expiresAt": "2025-01-24T15:30:00.0000000Z",
    "grantedAt": "2025-01-24T15:00:00.0000000Z",
    "isAdmin": true
}
```

### Connection Flow

```
1. CLIENT: Connect to \\.\pipe\MakeMeAdminCLI
2. CLIENT: Send JSON request via StreamWriter
3. SERVER: Read request (CRITICAL: must read before impersonation works)
4. SERVER: Call GetImpersonationUserName() to get client's Windows identity
5. SERVER: Validate requested username matches authenticated identity
6. SERVER: Process request (add to Administrators group, etc.)
7. SERVER: Send JSON response
8. SERVER: Disconnect pipe, create new instance for next client
```

---

## Security Model

### Identity Verification

The most critical security feature: **users can only elevate themselves**.

When a client connects to a named pipe with `PipeOptions.CurrentUserOnly` (implied by Authenticated Users ACL), Windows attaches the client's security token to the connection. The server retrieves this using `GetImpersonationUserName()`:

```powershell
function Get-PipeClientIdentity {
    param($PipeServer)

    # This only works AFTER reading from the pipe
    $pipeServer.GetImpersonationUserName()  # Returns "DOMAIN\username"
}
```

The server then validates:
```powershell
$authenticatedUser = Get-PipeClientIdentity -PipeServer $pipe
$requestedUser = $request.username

if ($authenticatedUser -ne $requestedUser) {
    # DENIED - user trying to elevate someone else
    return @{
        success = $false
        message = "You can only request admin rights for yourself"
    }
}
```

### Why This Can't Be Spoofed

1. **Windows handles authentication** - The identity comes from the client's security token, not from the JSON payload
2. **Impersonation level is Identification** - Server can read identity but client can't make server act as them
3. **Named pipes are local only** - No remote connections possible to `\\.\pipe\`
4. **ACL enforcement** - Only authenticated users can connect

### Access Control

Additional authorization via AllowedUsers/DeniedUsers:

```powershell
# DeniedUsers always takes precedence
if ($config.DeniedUsers -contains $username) {
    return $false  # DENIED
}

# Empty AllowedUsers = everyone allowed
if ($config.AllowedUsers.Count -eq 0) {
    return $true  # ALLOWED
}

# Check if user is in allowed list
return ($config.AllowedUsers -contains $username)
```

---

## Automatic Expiration System

### The Problem

If admin rights were only removed when the service processed a removal request, what happens if:
- The service crashes?
- The computer restarts during the elevation period?
- Network issues prevent the scheduled task service from communicating?

### The Solution: Independent Removal Tasks

When granting admin rights, the server creates a **separate scheduled task** that will fire at the expiration time:

```powershell
function New-AdminRemovalTask {
    param(
        [string]$Username,
        [datetime]$ExpiresAt
    )

    # Generate unique task name
    $taskName = "RemoveAdmin_$($Username -replace '[\\:]', '_')_$(Get-Date -Format 'yyyyMMddHHmmss')"

    # Create trigger for exact expiration time
    $trigger = New-ScheduledTaskTrigger -Once -At $ExpiresAt

    # Task runs as SYSTEM with highest privileges
    $principal = New-ScheduledTaskPrincipal `
        -UserId "NT AUTHORITY\SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    # Action: run the removal script
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

    # Critical settings for reliability
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable      # Run even if trigger was missed
        -AllowStartIfOnBatteries # Don't skip on laptops
        -DontStopIfGoingOnBatteries
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath `
        -Trigger $trigger -Action $action -Principal $principal -Settings $settings
}
```

### Removal Script with Retry Logic

The generated removal script includes retry logic for reliability:

```powershell
# Simplified version of the generated script
$maxAttempts = 3
$retryDelay = 30  # seconds

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        # Get Administrators group by SID (language-independent)
        $adminGroup = ([System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")).Translate(
            [System.Security.Principal.NTAccount]
        ).Value.Split('\')[-1]

        # Remove user from group
        Remove-LocalGroupMember -Group $adminGroup -Member $Username -ErrorAction Stop

        # Update state file
        $state = Get-Content $stateFile | ConvertFrom-Json
        $state.ActiveUsers = @($state.ActiveUsers | Where-Object { $_.Username -ne $Username })
        $state | ConvertTo-Json | Set-Content $stateFile

        # Self-cleanup: remove this task
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Remove-Item $scriptPath -Force

        exit 0  # Success
    }
    catch {
        if ($attempt -lt $maxAttempts) {
            Start-Sleep -Seconds $retryDelay
        }
    }
}
```

### Why This Is Robust

| Failure Scenario | Result |
|------------------|--------|
| Service crashes | Removal task still fires on schedule |
| Computer restarts | Task Scheduler runs task when it boots (StartWhenAvailable) |
| Service never restarts | Removal task is independent |
| First removal attempt fails | Retry logic tries 3 times |
| User manually extends time | Old removal task runs, but user is added again with new expiration |

---

## State Management

### State File (`C:\ProgramData\MakeMeAdminCLI\state.json`)

Tracks currently elevated users:

```json
{
    "ActiveUsers": [
        {
            "Username": "CONTOSO\\jsmith",
            "GrantedAt": "2025-01-24T15:00:00.0000000",
            "ExpiresAt": "2025-01-24T15:30:00.0000000",
            "TaskName": "RemoveAdmin_CONTOSO_jsmith_20250124150000"
        }
    ],
    "LastUpdated": "2025-01-24T15:00:00.0000000",
    "ServiceStartTime": "2025-01-24T08:00:00.0000000"
}
```

### Configuration File (`config.json`)

```json
{
    "DefaultDurationMinutes": 15,
    "MaxDurationMinutes": 60,
    "MinDurationMinutes": 1,
    "EventLogSource": "MakeMeAdminCLI",
    "AllowedUsers": [],
    "DeniedUsers": [],
    "PipeName": "MakeMeAdminCLI",
    "TaskPath": "\\Microsoft\\Windows\\MakeMeAdminCLI",
    "StateFilePath": null
}
```

### File Locations

| File | Path | Purpose |
|------|------|---------|
| Module | `C:\Program Files\WindowsPowerShell\Modules\MakeMeAdminCLI\` | PowerShell module |
| Config | `C:\ProgramData\MakeMeAdminCLI\config.json` | Runtime configuration |
| State | `C:\ProgramData\MakeMeAdminCLI\state.json` | Active user tracking |
| Scripts | `C:\ProgramData\MakeMeAdminCLI\Scripts\` | Removal task scripts |

---

## Event Logging

All operations are logged to Windows Event Log for auditing:

| Event ID | Level | Meaning |
|----------|-------|---------|
| 1000 | Information | Service started |
| 1001 | Information | Service stopped |
| 1005 | Information | Admin rights **granted** |
| 1006 | Information | Admin rights **removed** |
| 1050 | Warning | Request **denied** |
| 1020 | Error | Critical error |

Query logs:
```powershell
Get-EventLog -LogName Application -Source MakeMeAdminCLI -Newest 50
```

---

## Language Independence

The module uses Windows Security Identifiers (SIDs) instead of localized group names:

```powershell
# This works on ANY Windows language
$adminSID = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
$adminGroupName = $adminSID.Translate([System.Security.Principal.NTAccount]).Value

# Returns:
# - "BUILTIN\Administrators" (English)
# - "BUILTIN\Administratoren" (German)
# - "BUILTIN\Administrateurs" (French)
# - etc.
```

Well-known SIDs used:
- `S-1-5-32-544` - Local Administrators group
- `S-1-5-18` - NT AUTHORITY\SYSTEM
- `S-1-5-11` - Authenticated Users
