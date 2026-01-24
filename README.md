# MakeMeAdminCLI

A PowerShell module for granting temporary local administrator rights from the command line. Inspired by [MakeMeAdmin](https://github.com/pseymour/MakeMeAdmin), this CLI-focused implementation allows standard users to elevate themselves without requiring a GUI application.

## Features

- **Self-service elevation** - Standard users can request temporary admin rights without IT intervention
- **Automatic expiration** - Admin rights are automatically removed after a configurable timeout
- **CLI-first design** - All operations available from PowerShell command line
- **Language-independent** - Uses Windows SIDs instead of localized group names
- **Secure architecture** - Service runs as SYSTEM; users communicate via named pipes
- **Event logging** - All operations logged to Windows Event Log for auditing
- **Access control** - Allow/deny lists to control which users can request elevation

---

## Quick Start

### 1. Install (Run as Administrator)

```powershell
# Navigate to the module directory
cd .\MakeMeAdminCli

# Run the installer (requires elevation)
.\Install-MakeMeAdminCLI.ps1
```

### 2. Request Admin Rights (Run as Standard User)

```powershell
# Request temporary admin rights (default: 15 minutes)
Add-TempAdmin

# Request for a specific duration
Add-TempAdmin -DurationMinutes 30
```

### 3. Check Status

```powershell
# See current elevation status
Get-TempAdminStatus
```

### 4. Remove Admin Rights Early (Optional)

```powershell
# Relinquish admin rights before timeout
Remove-TempAdmin
```

---

## Installation

### Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- Administrator privileges (for installation only)

### Install

Run PowerShell as Administrator:

```powershell
# From the module source directory
.\Install-MakeMeAdminCLI.ps1

# Force reinstall if already installed
.\Install-MakeMeAdminCLI.ps1 -Force
```

The installer will:
- Copy the module to `C:\Program Files\WindowsPowerShell\Modules\MakeMeAdminCLI`
- Create a state directory at `C:\ProgramData\MakeMeAdminCLI`
- Register the Windows Event Log source
- Create and start a scheduled task that runs the service as SYSTEM

### Verify Installation

```powershell
.\Test-MakeMeAdminCLI.ps1
```

Expected output:
```
MakeMeAdminCLI Installation Test
================================
[PASS] Module installed at expected location
[PASS] Module manifest exists
[PASS] Module can be imported
[PASS] Service scheduled task exists
[PASS] Service is running
[PASS] Named pipe is accessible
[PASS] Event Log source registered
[PASS] State directory exists and is writable
[PASS] Configuration file exists
[PASS] Service script exists

All tests passed. MakeMeAdminCLI is ready to use.
```

### Uninstall

```powershell
# Complete removal
.\Uninstall-MakeMeAdminCLI.ps1

# Keep configuration for later reinstall
.\Uninstall-MakeMeAdminCLI.ps1 -KeepConfig

# Skip confirmation prompts
.\Uninstall-MakeMeAdminCLI.ps1 -Force
```

---

## Commands

### Add-TempAdmin

Request temporary administrator rights.

```powershell
# Use default duration (15 minutes)
Add-TempAdmin

# Specify duration
Add-TempAdmin -DurationMinutes 30

# Extend existing session without confirmation
Add-TempAdmin -DurationMinutes 60 -Force
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `-DurationMinutes` | Int | Duration in minutes (1-1440). Default: 15 |
| `-Force` | Switch | Extend existing elevation without confirmation |

**Aliases:** `mama`

**Output:**
```
Temporary admin rights granted.
Username   : DOMAIN\username
Expires At : 2025-01-23 14:30:00
Duration   : 30 minutes

Note: New processes will run with admin rights. Existing processes retain their current privileges.
```

---

### Remove-TempAdmin

Remove temporary admin rights before expiration.

```powershell
# With confirmation
Remove-TempAdmin

# Without confirmation
Remove-TempAdmin -Force
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `-Force` | Switch | Skip confirmation prompt |

**Aliases:** `rmadmin`

---

### Get-TempAdminStatus

Check current elevation status.

```powershell
# Current user status
Get-TempAdminStatus

# All elevated users (requires admin)
Get-TempAdminStatus -All
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `-All` | Switch | Show all elevated users (requires elevation) |

**Aliases:** `adminstatus`

**Output (Elevated):**
```
Status     : Elevated
Username   : DOMAIN\username
Expires At : 2025-01-23 14:30:00
Remaining  : 25 minutes 30 seconds
```

**Output (Not Elevated):**
```
Status     : Not Elevated
Username   : DOMAIN\username

You do not currently have temporary admin rights.
Use 'Add-TempAdmin' to request temporary elevation.
```

---

### Set-TempAdminConfig

View or modify configuration settings (requires elevation to modify).

```powershell
# View current configuration
Set-TempAdminConfig

# Change default duration
Set-TempAdminConfig -DefaultDurationMinutes 30

# Set duration limits
Set-TempAdminConfig -MinDurationMinutes 5 -MaxDurationMinutes 120

# Restrict to specific users
Set-TempAdminConfig -AllowedUsers @("DOMAIN\ITStaff", "DOMAIN\Developers")

# Block specific users
Set-TempAdminConfig -DeniedUsers @("DOMAIN\Contractors")

# Add a user to allowed list
Set-TempAdminConfig -AddAllowedUser "DOMAIN\NewUser"

# Remove a user from allowed list
Set-TempAdminConfig -RemoveAllowedUser "DOMAIN\OldUser"
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `-DefaultDurationMinutes` | Int | Default duration when not specified (1-1440) |
| `-MaxDurationMinutes` | Int | Maximum allowed duration (1-1440) |
| `-MinDurationMinutes` | Int | Minimum allowed duration (1-1440) |
| `-AllowedUsers` | String[] | Users/groups permitted to elevate (empty = all) |
| `-DeniedUsers` | String[] | Users/groups blocked from elevating |
| `-AddAllowedUser` | String | Add single user to allowed list |
| `-RemoveAllowedUser` | String | Remove single user from allowed list |
| `-AddDeniedUser` | String | Add single user to denied list |
| `-RemoveDeniedUser` | String | Remove single user from denied list |

---

## Configuration

Configuration is stored in JSON format at:
- Default config: `<ModulePath>\config.json`
- Runtime config: `C:\ProgramData\MakeMeAdminCLI\config.json`

### Default Configuration

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

### Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `DefaultDurationMinutes` | 15 | Duration when user doesn't specify |
| `MaxDurationMinutes` | 60 | Maximum allowed duration |
| `MinDurationMinutes` | 1 | Minimum allowed duration |
| `AllowedUsers` | [] | Users/groups that can request elevation. Empty = all allowed |
| `DeniedUsers` | [] | Users/groups blocked from elevation. Takes precedence over AllowedUsers |
| `EventLogSource` | "MakeMeAdminCLI" | Windows Event Log source name |
| `PipeName` | "MakeMeAdminCLI" | Named pipe for client-server communication |
| `TaskPath` | "\Microsoft\Windows\MakeMeAdminCLI" | Task Scheduler path for removal tasks |

### Access Control Examples

```powershell
# Allow only IT staff to request elevation
Set-TempAdminConfig -AllowedUsers @("DOMAIN\IT-Staff", "DOMAIN\Helpdesk")

# Allow everyone except contractors
Set-TempAdminConfig -AllowedUsers @() -DeniedUsers @("DOMAIN\Contractors")

# Use SIDs for reliability
Set-TempAdminConfig -AllowedUsers @("S-1-5-21-XXXX-XXXX-XXXX-1001")
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Standard User Session                        │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐ │
│  │ Add-TempAdmin│   │Remove-TempAdm│   │ Get-TempAdminStatus  │ │
│  └──────┬───────┘   └──────┬───────┘   └──────────┬───────────┘ │
│         │                  │                      │              │
│         └──────────────────┼──────────────────────┘              │
│                            │                                     │
│                    Named Pipe Client                             │
│                   (NamedPipe-Client.ps1)                         │
└────────────────────────────┼─────────────────────────────────────┘
                             │
                      Named Pipe IPC
                    "\\.\pipe\MakeMeAdminCLI"
                             │
┌────────────────────────────┼─────────────────────────────────────┐
│                     SYSTEM Context                               │
│                            │                                     │
│                    ┌───────┴───────┐                             │
│                    │ Service-Main  │ (Scheduled Task as SYSTEM)  │
│                    └───────┬───────┘                             │
│                            │                                     │
│         ┌──────────────────┼──────────────────┐                  │
│         │                  │                  │                  │
│  ┌──────┴──────┐   ┌───────┴──────┐   ┌──────┴───────┐          │
│  │ AdminGroup  │   │ScheduledTask │   │   Logging    │          │
│  │ Functions   │   │  Functions   │   │  Functions   │          │
│  └─────────────┘   └──────────────┘   └──────────────┘          │
│         │                  │                                     │
│  Local Admins      Task Scheduler        Event Log              │
│    Group        (Removal Tasks)        (Application)            │
└─────────────────────────────────────────────────────────────────┘
```

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **Service-Main.ps1** | Private/ | Named pipe server, request processing |
| **AdminGroup-Functions.ps1** | Private/ | Add/remove users from Administrators |
| **ScheduledTask-Functions.ps1** | Private/ | Create removal tasks with retry logic |
| **Config-Functions.ps1** | Private/ | Configuration management |
| **Logging-Functions.ps1** | Private/ | Event Log helpers |
| **NamedPipe-Client.ps1** | Private/ | Client-side pipe communication |

### Event Log

Events are logged to **Windows Logs > Application** with source **MakeMeAdminCLI**.

| Event ID | Level | Description |
|----------|-------|-------------|
| 1000 | Information | Service started |
| 1001 | Information | Service stopped |
| 1005 | Information | Admin rights granted |
| 1006 | Information | Admin rights removed |
| 1010 | Warning | Non-critical issues |
| 1020 | Error | Critical errors |

---

## Security Considerations

### How It Works

1. **Service runs as SYSTEM** - Only SYSTEM has permission to modify the local Administrators group
2. **Named pipe authentication** - Windows authenticates the pipe client; service validates identity
3. **User isolation** - Users can only request elevation for themselves, not others
4. **Automatic removal** - Scheduled tasks ensure admin rights don't persist indefinitely
5. **Retry logic** - Multiple removal attempts if initial removal fails

### Important Notes

- **Existing processes keep their token** - After elevation, new processes get admin rights; existing processes do not. Sign out and back in for full effect.
- **Removal tasks persist** - Even if the service stops, scheduled removal tasks will still execute
- **Deny takes precedence** - DeniedUsers list overrides AllowedUsers list

### Recommendations

1. **Use AllowedUsers** - Restrict elevation to specific groups (e.g., IT staff, developers)
2. **Monitor Event Log** - Review elevation requests periodically
3. **Set MaxDuration** - Limit maximum elevation time to reduce risk window
4. **Combine with other controls** - Use alongside Intune policies, LAPS, or PAM solutions

---

## Troubleshooting

### Service Not Running

```
Error: MakeMeAdminCLI service is not running.
```

**Solution:** Run the installer as Administrator:
```powershell
.\Install-MakeMeAdminCLI.ps1 -Force
```

Or manually start the scheduled task:
```powershell
Start-ScheduledTask -TaskPath "\Microsoft\Windows\MakeMeAdminCLI" -TaskName "MakeMeAdminCLI-Service"
```

### Access Denied

```
Error: Your account is not authorized to request admin rights.
```

**Solution:** Check the AllowedUsers/DeniedUsers configuration:
```powershell
# Run as admin
Set-TempAdminConfig
```

### Module Not Found

```
Error: The term 'Add-TempAdmin' is not recognized...
```

**Solution:** Import the module or verify installation:
```powershell
Import-Module MakeMeAdminCLI
# Or verify installation
.\Test-MakeMeAdminCLI.ps1
```

### Admin Rights Not Working

New processes don't have admin rights after `Add-TempAdmin` succeeds.

**Solution:** This is expected Windows behavior. Start a new process (e.g., new PowerShell window) or sign out and back in.

### Check Service Logs

```powershell
# View recent MakeMeAdminCLI events
Get-EventLog -LogName Application -Source MakeMeAdminCLI -Newest 20
```

---

## File Structure

```
MakeMeAdminCLI/
├── MakeMeAdminCLI.psd1           # Module manifest
├── MakeMeAdminCLI.psm1           # Module loader
├── config.json                    # Default configuration
├── Install-MakeMeAdminCLI.ps1    # Installation script
├── Uninstall-MakeMeAdminCLI.ps1  # Uninstallation script
├── Test-MakeMeAdminCLI.ps1       # Installation verification
├── README.md                      # This file
├── Private/
│   ├── Service-Main.ps1          # Named pipe server
│   ├── AdminGroup-Functions.ps1  # Admin group manipulation
│   ├── ScheduledTask-Functions.ps1 # Removal task management
│   ├── Config-Functions.ps1      # Configuration helpers
│   ├── Logging-Functions.ps1     # Event logging
│   └── NamedPipe-Client.ps1      # Client communication
└── Public/
    ├── Add-TempAdmin.ps1         # Request elevation
    ├── Remove-TempAdmin.ps1      # Remove elevation
    ├── Get-TempAdminStatus.ps1   # Check status
    └── Set-TempAdminConfig.ps1   # Configure settings
```

---

## License

This project is provided as-is for educational and administrative purposes.

## Acknowledgments

- Inspired by [MakeMeAdmin](https://github.com/pseymour/MakeMeAdmin) by Sinclair Community College
- Original AddTempAdminRights script by Pavel Mirochnitchenko MVP
