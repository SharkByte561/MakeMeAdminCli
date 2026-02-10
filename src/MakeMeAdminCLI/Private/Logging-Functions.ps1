#Requires -Version 5.1
<#
.SYNOPSIS
    Event logging functions for MakeMeAdminCLI.

.DESCRIPTION
    Provides functions to write events to the Windows Application Event Log
    and manage the event log source for MakeMeAdminCLI.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0

    Event IDs:
    - 1000: Service started
    - 1001: Service stopped
    - 1005: Admin rights granted
    - 1006: Admin rights removed
    - 1010: Warning (general)
    - 1020: Error (general)
    - 1030: Configuration change
    - 1040: Request received
    - 1050: Request denied
    - 1060: Process launched
#>

# Event ID constants
$script:EventIds = @{
    ServiceStarted = 1000
    ServiceStopped = 1001
    AdminRightsGranted = 1005
    AdminRightsRemoved = 1006
    Warning = 1010
    Error = 1020
    ConfigChange = 1030
    RequestReceived = 1040
    RequestDenied = 1050
    ProcessLaunched = 1060
}

# Default event source
$script:DefaultEventSource = "MakeMeAdminCLI"
$script:LogName = "Application"

function Initialize-MakeMeAdminEventLog {
    <#
    .SYNOPSIS
        Initializes the Windows Event Log source for MakeMeAdminCLI.

    .DESCRIPTION
        Creates the event log source if it doesn't exist. This operation requires
        administrative privileges.

    .PARAMETER EventSource
        The name of the event source to create. Defaults to "MakeMeAdminCLI".

    .EXAMPLE
        Initialize-MakeMeAdminEventLog

    .EXAMPLE
        Initialize-MakeMeAdminEventLog -EventSource "MyCustomSource"
    #>
    [CmdletBinding()]
    param(
        [string]$EventSource = $script:DefaultEventSource
    )

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $script:LogName)
            Write-Verbose "Event log source '$EventSource' created successfully."
        } else {
            Write-Verbose "Event log source '$EventSource' already exists."
        }
        return $true
    }
    catch [System.Security.SecurityException] {
        Write-Warning "Administrative privileges required to create event log source '$EventSource'."
        return $false
    }
    catch {
        Write-Warning "Failed to create event log source '$EventSource': $($_.Exception.Message)"
        return $false
    }
}

function Get-SafeEventSource {
    <#
    .SYNOPSIS
        Gets a valid event source for writing to the Application log.

    .DESCRIPTION
        Attempts to use the preferred event source. If it doesn't exist and cannot
        be created, falls back to a built-in source that's always available.

    .PARAMETER PreferredSource
        The preferred event source name.

    .OUTPUTS
        String containing a valid event source name, or $null if none available.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$PreferredSource = $script:DefaultEventSource
    )

    try {
        # Try the preferred source first
        if ($PreferredSource -and [System.Diagnostics.EventLog]::SourceExists($PreferredSource)) {
            return $PreferredSource
        }

        # Fallback to well-known sources
        $fallbackSources = @(
            'Application',
            'Windows PowerShell',
            'EventLog',
            'MsiInstaller',
            'Application Error',
            'Windows Error Reporting'
        )

        foreach ($source in $fallbackSources) {
            try {
                if ([System.Diagnostics.EventLog]::SourceExists($source)) {
                    return $source
                }
            }
            catch {
                continue
            }
        }
    }
    catch {
        Write-Verbose "Error finding event source: $($_.Exception.Message)"
    }

    return $null
}

function Write-MakeMeAdminLog {
    <#
    .SYNOPSIS
        Writes an entry to the Windows Event Log.

    .DESCRIPTION
        Writes an event to the Application event log using the MakeMeAdminCLI
        event source, or a fallback source if necessary.

    .PARAMETER Message
        The message to log.

    .PARAMETER EventId
        The event ID. Defaults to 1000.

    .PARAMETER EntryType
        The type of event: Information, Warning, or Error. Defaults to Information.

    .PARAMETER EventSource
        The event source to use. Defaults to the configured source.

    .EXAMPLE
        Write-MakeMeAdminLog -Message "Admin rights granted to DOMAIN\User" -EventId 1005

    .EXAMPLE
        Write-MakeMeAdminLog -Message "Failed to remove user" -EventId 1020 -EntryType Error
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [int]$EventId = 1000,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$EntryType = 'Information',

        [string]$EventSource
    )

    # Get the configured event source if not specified
    if (-not $EventSource) {
        try {
            # Try to get from config, but don't fail if config isn't available yet
            $configPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config.json"
            if (Test-Path $configPath) {
                $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                $EventSource = $config.EventLogSource
            }
        }
        catch {
            # Ignore errors, use default
        }
        if (-not $EventSource) {
            $EventSource = $script:DefaultEventSource
        }
    }

    # Get a valid event source
    $validSource = Get-SafeEventSource -PreferredSource $EventSource

    if ($null -eq $validSource) {
        Write-Warning "No valid event log source available. Message not logged to Event Viewer: $Message"
        return
    }

    try {
        Write-EventLog -LogName $script:LogName `
                       -Source $validSource `
                       -EventId $EventId `
                       -EntryType $EntryType `
                       -Message $Message
        Write-Verbose "Event logged: [$EntryType] EventId=$EventId Source=$validSource"
    }
    catch {
        Write-Warning "Failed to write to Event Log: $($_.Exception.Message)"
        Write-Warning "Original message: $Message"
    }
}

function Write-ServiceStartedEvent {
    <#
    .SYNOPSIS
        Logs that the MakeMeAdminCLI service has started.
    #>
    [CmdletBinding()]
    param(
        [string]$AdditionalInfo = ""
    )

    $message = "MakeMeAdminCLI service started."
    if ($AdditionalInfo) {
        $message += " $AdditionalInfo"
    }

    Write-MakeMeAdminLog -Message $message `
                         -EventId $script:EventIds.ServiceStarted `
                         -EntryType Information
}

function Write-ServiceStoppedEvent {
    <#
    .SYNOPSIS
        Logs that the MakeMeAdminCLI service has stopped.
    #>
    [CmdletBinding()]
    param(
        [string]$Reason = ""
    )

    $message = "MakeMeAdminCLI service stopped."
    if ($Reason) {
        $message += " Reason: $Reason"
    }

    Write-MakeMeAdminLog -Message $message `
                         -EventId $script:EventIds.ServiceStopped `
                         -EntryType Information
}

function Write-AdminRightsGrantedEvent {
    <#
    .SYNOPSIS
        Logs that temporary admin rights were granted to a user.

    .PARAMETER Username
        The username that was granted admin rights.

    .PARAMETER DurationMinutes
        The duration for which admin rights were granted.

    .PARAMETER ExpiresAt
        The datetime when the admin rights will expire.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [int]$DurationMinutes,

        [Parameter(Mandatory)]
        [datetime]$ExpiresAt
    )

    $message = "Temporary administrator rights granted to '$Username' for $DurationMinutes minutes. Expires at: $($ExpiresAt.ToString('yyyy-MM-dd HH:mm:ss'))"

    Write-MakeMeAdminLog -Message $message `
                         -EventId $script:EventIds.AdminRightsGranted `
                         -EntryType Information
}

function Write-AdminRightsRemovedEvent {
    <#
    .SYNOPSIS
        Logs that admin rights were removed from a user.

    .PARAMETER Username
        The username that had admin rights removed.

    .PARAMETER Reason
        The reason for removal (Timeout, UserRequest, ServiceStopped, etc.)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [ValidateSet('Timeout', 'UserRequest', 'ServiceStopped', 'Manual', 'Unknown')]
        [string]$Reason = 'Unknown'
    )

    $message = "Administrator rights removed from '$Username'. Reason: $Reason"

    Write-MakeMeAdminLog -Message $message `
                         -EventId $script:EventIds.AdminRightsRemoved `
                         -EntryType Information
}

function Write-RequestReceivedEvent {
    <#
    .SYNOPSIS
        Logs that a request for admin rights was received.

    .PARAMETER Username
        The username that made the request.

    .PARAMETER Action
        The requested action (add, remove, status).

    .PARAMETER RequestedDuration
        The requested duration in minutes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Action,

        [int]$RequestedDuration = 0
    )

    $message = "Request received from '$Username'. Action: $Action"
    if ($RequestedDuration -gt 0) {
        $message += ", Requested duration: $RequestedDuration minutes"
    }

    Write-MakeMeAdminLog -Message $message `
                         -EventId $script:EventIds.RequestReceived `
                         -EntryType Information
}

function Write-RequestDeniedEvent {
    <#
    .SYNOPSIS
        Logs that a request for admin rights was denied.

    .PARAMETER Username
        The username that made the request.

    .PARAMETER Reason
        The reason for denial.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    $message = "Request denied for '$Username'. Reason: $Reason"

    Write-MakeMeAdminLog -Message $message `
                         -EventId $script:EventIds.RequestDenied `
                         -EntryType Warning
}

function Write-ProcessLaunchedEvent {
    <#
    .SYNOPSIS
        Logs that a process was launched via the exec action.

    .PARAMETER Username
        The username that requested the process launch.

    .PARAMETER ProgramPath
        The full path of the program that was launched.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$ProgramPath
    )

    $message = "Process launched for '$Username'. Program: $ProgramPath"

    Write-MakeMeAdminLog -Message $message `
                         -EventId $script:EventIds.ProcessLaunched `
                         -EntryType Information
}

function Write-WarningEvent {
    <#
    .SYNOPSIS
        Logs a warning event.

    .PARAMETER Message
        The warning message to log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-MakeMeAdminLog -Message $Message `
                         -EventId $script:EventIds.Warning `
                         -EntryType Warning
}

function Write-ErrorEvent {
    <#
    .SYNOPSIS
        Logs an error event.

    .PARAMETER Message
        The error message to log.

    .PARAMETER Exception
        Optional exception object for additional details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [System.Exception]$Exception = $null
    )

    $fullMessage = $Message
    if ($Exception) {
        $fullMessage += "`nException: $($Exception.GetType().FullName)`nDetails: $($Exception.Message)"
    }

    Write-MakeMeAdminLog -Message $fullMessage `
                         -EventId $script:EventIds.Error `
                         -EntryType Error
}

# Export module members (when dot-sourced from module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Initialize-MakeMeAdminEventLog',
        'Get-SafeEventSource',
        'Write-MakeMeAdminLog',
        'Write-ServiceStartedEvent',
        'Write-ServiceStoppedEvent',
        'Write-AdminRightsGrantedEvent',
        'Write-AdminRightsRemovedEvent',
        'Write-RequestReceivedEvent',
        'Write-RequestDeniedEvent',
        'Write-ProcessLaunchedEvent',
        'Write-WarningEvent',
        'Write-ErrorEvent'
    )

    Export-ModuleMember -Variable 'EventIds'
}
