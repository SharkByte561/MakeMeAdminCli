#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    MakeMeAdminCLI Named Pipe Server - Main service script.

.DESCRIPTION
    This script implements a named pipe server that listens for requests from
    non-elevated users to grant temporary administrator rights. It runs as
    SYSTEM (either as a Windows service or a scheduled task) and handles:

    - Adding users to the local Administrators group
    - Creating scheduled tasks to remove users after the configured timeout
    - Processing status queries about active elevated users
    - Validating that requesters match the authenticated pipe client

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0

    This script should be run as SYSTEM via a Windows service or scheduled task.

    Named Pipe Protocol:
    - Pipe Name: MakeMeAdminCLI (configurable)
    - Request Format: JSON { "action": "add|remove|status|exec", "username": "DOMAIN\\user", "duration": 15 }
    - Exec Format: JSON { "action": "exec", "program": "C:\\path\\to\\app.exe", "arguments": "...", "workingDirectory": "..." }
    - Response Format: JSON { "success": true|false, "message": "...", "expiresAt": "ISO8601 datetime" }

.PARAMETER RunOnce
    If specified, processes a single request and exits instead of running continuously.

.PARAMETER Timeout
    The timeout in seconds for each pipe connection. Defaults to 30 seconds.

.EXAMPLE
    # Run as a continuous service
    .\Service-Main.ps1

.EXAMPLE
    # Run once for testing
    .\Service-Main.ps1 -RunOnce
#>

[CmdletBinding()]
param(
    [switch]$RunOnce,
    [int]$Timeout = 30
)

# Relaunch in 64-bit PowerShell if currently in 32-bit
if (-not [Environment]::Is64BitProcess) {
    $ps64 = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $ps64) {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($RunOnce) { $arguments += " -RunOnce" }
        $arguments += " -Timeout $Timeout"
        & $ps64 $arguments.Split(' ')
        exit $LASTEXITCODE
    }
}

$ErrorActionPreference = 'Stop'

# Get script directory and load dependencies
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ModuleRoot = Split-Path -Parent $ScriptRoot

# Dot-source the helper function files
. (Join-Path $ScriptRoot "Config-Functions.ps1")
. (Join-Path $ScriptRoot "Logging-Functions.ps1")
. (Join-Path $ScriptRoot "AdminGroup-Functions.ps1")
. (Join-Path $ScriptRoot "ScheduledTask-Functions.ps1")

# Global state
$script:Running = $true
$script:ActiveServer = $null

#region State Management

function Initialize-StateFile {
    <#
    .SYNOPSIS
        Initializes or loads the state file for tracking active elevated users.
    #>
    [CmdletBinding()]
    param()

    $stateFilePath = Get-StateFilePath
    $stateFolder = Split-Path -Parent $stateFilePath

    # Ensure folder exists
    if (-not (Test-Path $stateFolder)) {
        New-Item -ItemType Directory -Path $stateFolder -Force | Out-Null
    }

    if (Test-Path $stateFilePath) {
        try {
            $state = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json
            # Validate structure
            if (-not $state.ActiveUsers) {
                $state | Add-Member -NotePropertyName "ActiveUsers" -NotePropertyValue @() -Force
            }
            return $state
        }
        catch {
            Write-Warning "Corrupted state file. Creating new one."
        }
    }

    # Create new state
    $state = [PSCustomObject]@{
        ActiveUsers = @()
        LastUpdated = (Get-Date).ToString('o')
        ServiceStartTime = (Get-Date).ToString('o')
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFilePath -Encoding UTF8 -Force
    return $state
}

function Save-State {
    <#
    .SYNOPSIS
        Saves the current state to the state file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State
    )

    $stateFilePath = Get-StateFilePath
    $State.LastUpdated = (Get-Date).ToString('o')
    $State | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFilePath -Encoding UTF8 -Force
}

function Add-ActiveUser {
    <#
    .SYNOPSIS
        Adds a user to the active elevated users list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [datetime]$ExpiresAt,

        [string]$TaskName
    )

    $state = Initialize-StateFile

    # Remove any existing entry for this user
    $state.ActiveUsers = @($state.ActiveUsers | Where-Object { $_.Username -ne $Username })

    # Add new entry
    $userEntry = [PSCustomObject]@{
        Username = $Username
        GrantedAt = (Get-Date).ToString('o')
        ExpiresAt = $ExpiresAt.ToString('o')
        TaskName = $TaskName
    }

    $state.ActiveUsers = @($state.ActiveUsers) + $userEntry
    Save-State -State $state
}

function Remove-ActiveUser {
    <#
    .SYNOPSIS
        Removes a user from the active elevated users list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    $state = Initialize-StateFile
    $state.ActiveUsers = @($state.ActiveUsers | Where-Object { $_.Username -ne $Username })
    Save-State -State $state
}

function Get-ActiveUsers {
    <#
    .SYNOPSIS
        Gets the list of currently elevated users.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $state = Initialize-StateFile
    return @($state.ActiveUsers)
}

#endregion

#region Named Pipe Server

function New-NamedPipeServer {
    <#
    .SYNOPSIS
        Creates a new named pipe server instance.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PipeName
    )

    try {
        # Create pipe security that allows authenticated users to connect
        $pipeSecurity = New-Object System.IO.Pipes.PipeSecurity

        # Allow SYSTEM full control
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $systemRule = New-Object System.IO.Pipes.PipeAccessRule($systemSid, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)
        $pipeSecurity.AddAccessRule($systemRule)

        # Allow Administrators full control
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $adminRule = New-Object System.IO.Pipes.PipeAccessRule($adminSid, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)
        $pipeSecurity.AddAccessRule($adminRule)

        # Allow authenticated users to read/write (they need to connect to make requests)
        $authUsersSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::AuthenticatedUserSid, $null)
        $authUsersRule = New-Object System.IO.Pipes.PipeAccessRule($authUsersSid, [System.IO.Pipes.PipeAccessRights]::ReadWrite, [System.Security.AccessControl.AccessControlType]::Allow)
        $pipeSecurity.AddAccessRule($authUsersRule)

        # Create the named pipe server
        $pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream(
            $PipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            1,  # Max instances
            [System.IO.Pipes.PipeTransmissionMode]::Message,
            [System.IO.Pipes.PipeOptions]::Asynchronous,
            4096,  # In buffer size
            4096,  # Out buffer size
            $pipeSecurity
        )

        return $pipeServer
    }
    catch {
        Write-Error "Failed to create named pipe server: $($_.Exception.Message)"
        return $null
    }
}

function Get-PipeClientIdentity {
    <#
    .SYNOPSIS
        Gets the identity of the connected pipe client.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Pipes.NamedPipeServerStream]$PipeServer
    )

    try {
        # Get the client's Windows identity
        $pipeServer.RunAsClient({
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        })
    }
    catch {
        Write-Warning "Could not get pipe client identity: $($_.Exception.Message)"
        return $null
    }
}

function Read-PipeMessage {
    <#
    .SYNOPSIS
        Reads a JSON message from the named pipe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Pipes.NamedPipeServerStream]$PipeServer,

        [int]$TimeoutSeconds = 30
    )

    try {
        $reader = New-Object System.IO.StreamReader($PipeServer)

        # Read with timeout
        $readTask = $reader.ReadLineAsync()
        $completed = $readTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))

        if (-not $completed) {
            Write-Warning "Pipe read timeout"
            return $null
        }

        $message = $readTask.Result
        if ([string]::IsNullOrWhiteSpace($message)) {
            return $null
        }

        # Parse JSON
        return $message | ConvertFrom-Json
    }
    catch {
        Write-Warning "Error reading pipe message: $($_.Exception.Message)"
        return $null
    }
}

function Write-PipeResponse {
    <#
    .SYNOPSIS
        Writes a JSON response to the named pipe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Pipes.NamedPipeServerStream]$PipeServer,

        [Parameter(Mandatory)]
        [PSCustomObject]$Response
    )

    try {
        $writer = New-Object System.IO.StreamWriter($PipeServer)
        $writer.AutoFlush = $true

        $json = $Response | ConvertTo-Json -Compress
        $writer.WriteLine($json)
    }
    catch {
        Write-Warning "Error writing pipe response: $($_.Exception.Message)"
    }
}

function New-Response {
    <#
    .SYNOPSIS
        Creates a standard response object.
    #>
    [CmdletBinding()]
    param(
        [bool]$Success,
        [string]$Message,
        [datetime]$ExpiresAt = [datetime]::MinValue,
        [PSCustomObject[]]$ActiveUsers = @()
    )

    $response = [PSCustomObject]@{
        success = $Success
        message = $Message
    }

    if ($ExpiresAt -ne [datetime]::MinValue) {
        $response | Add-Member -NotePropertyName "expiresAt" -NotePropertyValue $ExpiresAt.ToString('o')
    }

    if ($ActiveUsers.Count -gt 0) {
        $response | Add-Member -NotePropertyName "activeUsers" -NotePropertyValue $ActiveUsers
    }

    return $response
}

#endregion

#region Request Handlers

function Invoke-AddRequest {
    <#
    .SYNOPSIS
        Handles a request to add a user to the Administrators group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$ClientIdentity,

        [int]$RequestedDuration = 0
    )

    Write-Verbose "Processing ADD request for '$Username' from '$ClientIdentity'"

    # Validate that the client identity matches the requested user
    # Allow for different domain\user formats
    $clientUser = $ClientIdentity
    $requestedUser = $Username

    # Normalize usernames for comparison
    $normalizedClient = $clientUser -replace '^[^\\]+\\', ''
    $normalizedRequested = $requestedUser -replace '^[^\\]+\\', ''

    if ($normalizedClient -ne $normalizedRequested) {
        Write-RequestDeniedEvent -Username $Username -Reason "Client identity '$ClientIdentity' does not match requested username '$Username'"
        return New-Response -Success $false -Message "Access denied: You can only request admin rights for yourself."
    }

    # Check if user is allowed
    $userSid = Get-UserSID -Username $Username
    if (-not (Test-UserAllowed -Username $Username -UserSID $userSid)) {
        Write-RequestDeniedEvent -Username $Username -Reason "User is not in allowed list or is in denied list"
        return New-Response -Success $false -Message "Access denied: You are not authorized to request admin rights."
    }

    # Get validated duration
    $duration = Get-ValidatedDuration -RequestedDuration $RequestedDuration
    $expiresAt = (Get-Date).AddMinutes($duration)

    # Add user to Administrators group
    $addResult = Add-UserToLocalAdmins -Username $Username

    if (-not $addResult.Success) {
        Write-ErrorEvent -Message "Failed to add '$Username' to Administrators: $($addResult.Message)"
        return New-Response -Success $false -Message $addResult.Message
    }

    # Create scheduled task for removal
    $taskResult = New-AdminRemovalTask -Username $Username -ExecuteAt $expiresAt

    if (-not $taskResult.Success) {
        Write-WarningEvent -Message "User '$Username' added to Administrators but removal task could not be created: $($taskResult.Message)"
        # Still return success since the user was added, but warn about the task
        $message = "Admin rights granted until $($expiresAt.ToString('HH:mm:ss')). WARNING: Automatic removal task could not be created."
    }
    else {
        # Track active user in state
        Add-ActiveUser -Username $Username -ExpiresAt $expiresAt -TaskName $taskResult.TaskName
        $message = "Admin rights granted until $($expiresAt.ToString('HH:mm:ss'))."
    }

    # Log the event
    Write-AdminRightsGrantedEvent -Username $Username -DurationMinutes $duration -ExpiresAt $expiresAt

    return New-Response -Success $true -Message $message -ExpiresAt $expiresAt
}

function Invoke-RemoveRequest {
    <#
    .SYNOPSIS
        Handles a request to remove a user from the Administrators group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$ClientIdentity
    )

    Write-Verbose "Processing REMOVE request for '$Username' from '$ClientIdentity'"

    # Validate that the client identity matches the requested user
    $normalizedClient = $ClientIdentity -replace '^[^\\]+\\', ''
    $normalizedRequested = $Username -replace '^[^\\]+\\', ''

    if ($normalizedClient -ne $normalizedRequested) {
        Write-RequestDeniedEvent -Username $Username -Reason "Client identity '$ClientIdentity' does not match requested username '$Username'"
        return New-Response -Success $false -Message "Access denied: You can only remove admin rights for yourself."
    }

    # Remove user from Administrators group
    $removeResult = Remove-UserFromLocalAdmins -Username $Username

    if ($removeResult.Success) {
        # Update state
        Remove-ActiveUser -Username $Username

        # Try to remove any pending removal task
        $activeUsers = Get-ActiveUsers
        $userEntry = $activeUsers | Where-Object { $_.Username -eq $Username }
        if ($userEntry -and $userEntry.TaskName) {
            Remove-AdminRemovalTask -TaskName $userEntry.TaskName -ErrorAction SilentlyContinue
        }

        # Log the event
        Write-AdminRightsRemovedEvent -Username $Username -Reason "UserRequest"

        return New-Response -Success $true -Message "Admin rights removed successfully."
    }
    else {
        return New-Response -Success $false -Message $removeResult.Message
    }
}

function Invoke-StatusRequest {
    <#
    .SYNOPSIS
        Handles a status query request.
    #>
    [CmdletBinding()]
    param(
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$ClientIdentity
    )

    Write-Verbose "Processing STATUS request from '$ClientIdentity'"

    $activeUsers = Get-ActiveUsers

    # If a specific username is requested, filter for that user
    if ($Username) {
        $normalizedRequested = $Username -replace '^[^\\]+\\', ''
        $normalizedClient = $ClientIdentity -replace '^[^\\]+\\', ''

        # Users can only query their own status
        if ($normalizedClient -ne $normalizedRequested) {
            return New-Response -Success $false -Message "Access denied: You can only query your own status."
        }

        $userEntry = $activeUsers | Where-Object {
            ($_.Username -replace '^[^\\]+\\', '') -eq $normalizedRequested
        }

        if ($userEntry) {
            $expiresAt = [datetime]::Parse($userEntry.ExpiresAt)
            $isAdmin = Test-UserIsLocalAdmin -Username $Username

            return [PSCustomObject]@{
                success = $true
                message = "User has active admin rights."
                isAdmin = $isAdmin
                expiresAt = $userEntry.ExpiresAt
                grantedAt = $userEntry.GrantedAt
            }
        }
        else {
            $isAdmin = Test-UserIsLocalAdmin -Username $Username
            return [PSCustomObject]@{
                success = $true
                message = if ($isAdmin) { "User is admin but not tracked by MakeMeAdminCLI." } else { "User does not have active admin rights." }
                isAdmin = $isAdmin
            }
        }
    }
    else {
        # Return general status (for the calling user)
        $normalizedClient = $ClientIdentity -replace '^[^\\]+\\', ''
        $userEntry = $activeUsers | Where-Object {
            ($_.Username -replace '^[^\\]+\\', '') -eq $normalizedClient
        }

        $isAdmin = Test-UserIsLocalAdmin -Username $ClientIdentity

        if ($userEntry) {
            return [PSCustomObject]@{
                success = $true
                message = "You have active admin rights."
                isAdmin = $isAdmin
                expiresAt = $userEntry.ExpiresAt
                grantedAt = $userEntry.GrantedAt
            }
        }
        else {
            return [PSCustomObject]@{
                success = $true
                message = if ($isAdmin) { "You are admin but not tracked by MakeMeAdminCLI." } else { "You do not have active admin rights." }
                isAdmin = $isAdmin
            }
        }
    }
}

function Invoke-ExecRequest {
    <#
    .SYNOPSIS
        Handles a request to launch a process on the user's desktop via ServiceUI.exe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Request,

        [Parameter(Mandatory)]
        [string]$ClientIdentity
    )

    Write-Verbose "Processing EXEC request from '$ClientIdentity'"

    $normalizedClient = $ClientIdentity -replace '^[^\\]+\\', ''

    # Check user has active elevation
    $activeUsers = Get-ActiveUsers
    $userEntry = $activeUsers | Where-Object {
        ($_.Username -replace '^[^\\]+\\', '') -eq $normalizedClient
    }

    if (-not $userEntry) {
        Write-RequestDeniedEvent -Username $ClientIdentity -Reason "No active elevation session for exec request"
        return New-Response -Success $false -Message "Access denied: You do not have an active elevation session. Run 'Add-TempAdmin' first."
    }

    # Validate program path
    $programPath = $Request.program
    if (-not $programPath -or -not (Test-Path $programPath)) {
        return New-Response -Success $false -Message "Program not found: '$programPath'. Provide a valid program path."
    }

    # Locate ServiceUI.exe relative to module root
    $serviceUIPath = Join-Path $ModuleRoot "ServiceUI.exe"
    if (-not (Test-Path $serviceUIPath)) {
        Write-ErrorEvent -Message "ServiceUI.exe not found at '$serviceUIPath'"
        return New-Response -Success $false -Message "ServiceUI.exe not found. Reinstall MakeMeAdminCLI."
    }

    # Build ServiceUI arguments
    # ServiceUI.exe -process:explorer.exe "program" arguments
    $serviceUIArgs = "-process:explorer.exe `"$programPath`""

    if ($Request.arguments) {
        $serviceUIArgs += " $($Request.arguments)"
    }

    try {
        Write-Verbose "Launching: $serviceUIPath $serviceUIArgs"

        $startParams = @{
            FilePath     = $serviceUIPath
            ArgumentList = $serviceUIArgs
            NoNewWindow  = $true
        }

        if ($Request.workingDirectory -and (Test-Path $Request.workingDirectory -PathType Container)) {
            $startParams['WorkingDirectory'] = $Request.workingDirectory
        }

        Start-Process @startParams

        # Log the event
        Write-ProcessLaunchedEvent -Username $ClientIdentity -ProgramPath $programPath

        return New-Response -Success $true -Message "Process launched: $programPath"
    }
    catch {
        Write-ErrorEvent -Message "Failed to launch process for '$ClientIdentity': $($_.Exception.Message)" -Exception $_.Exception
        return New-Response -Success $false -Message "Failed to launch process: $($_.Exception.Message)"
    }
}

function Invoke-Request {
    <#
    .SYNOPSIS
        Routes a request to the appropriate handler.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Request,

        [Parameter(Mandatory)]
        [string]$ClientIdentity
    )

    $action = $Request.action
    $username = if ($Request.username) { $Request.username } else { $ClientIdentity }
    $duration = if ($Request.duration) { [int]$Request.duration } else { 0 }

    Write-RequestReceivedEvent -Username $ClientIdentity -Action $action -RequestedDuration $duration

    switch ($action.ToLower()) {
        'add' {
            return Invoke-AddRequest -Username $username -ClientIdentity $ClientIdentity -RequestedDuration $duration
        }
        'remove' {
            return Invoke-RemoveRequest -Username $username -ClientIdentity $ClientIdentity
        }
        'status' {
            return Invoke-StatusRequest -Username $username -ClientIdentity $ClientIdentity
        }
        'exec' {
            return Invoke-ExecRequest -Request $Request -ClientIdentity $ClientIdentity
        }
        default {
            return New-Response -Success $false -Message "Unknown action: $action. Valid actions are: add, remove, status, exec."
        }
    }
}

#endregion

#region Main Service Loop

function Start-ServiceLoop {
    <#
    .SYNOPSIS
        Main service loop that listens for and processes requests.
    #>
    [CmdletBinding()]
    param(
        [switch]$RunOnce,
        [int]$TimeoutSeconds = 30
    )

    $config = Get-MakeMeAdminConfig
    $pipeName = $config.PipeName

    Write-Verbose "Starting MakeMeAdminCLI service..."
    Write-Verbose "Pipe name: $pipeName"
    Write-Verbose "Config file: $(Join-Path $ModuleRoot 'config.json')"
    Write-Verbose "State file: $($config.StateFilePath)"

    # Initialize event log
    $null = Initialize-MakeMeAdminEventLog -EventSource $config.EventLogSource

    # Initialize state
    $null = Initialize-StateFile

    # Log service start
    Write-ServiceStartedEvent -AdditionalInfo "Listening on pipe: $pipeName"

    try {
        while ($script:Running) {
            $pipeServer = $null

            try {
                # Create new pipe server for each connection
                $pipeServer = New-NamedPipeServer -PipeName $pipeName

                if ($null -eq $pipeServer) {
                    Write-Warning "Failed to create pipe server. Retrying in 5 seconds..."
                    Start-Sleep -Seconds 5
                    continue
                }

                Write-Verbose "Waiting for connection on pipe: $pipeName"

                # Wait for a connection
                $pipeServer.WaitForConnection()

                Write-Verbose "Client connected"

                # Read the request FIRST (required before GetImpersonationUserName can work)
                $request = Read-PipeMessage -PipeServer $pipeServer -TimeoutSeconds $TimeoutSeconds

                # Now get client identity using GetImpersonationUserName (must be after reading data)
                $clientIdentity = "Unknown"
                try {
                    $impersonationName = $pipeServer.GetImpersonationUserName()
                    Write-Verbose "GetImpersonationUserName returned: '$impersonationName'"
                    if ($impersonationName) {
                        $clientIdentity = $impersonationName
                    }
                }
                catch {
                    Write-Warning "Could not get client identity via GetImpersonationUserName: $($_.Exception.Message)"
                }

                Write-Verbose "Client identity: $clientIdentity"

                if ($null -eq $request) {
                    Write-Verbose "No valid request received"
                    $response = New-Response -Success $false -Message "Invalid request format. Expected JSON."
                }
                else {
                    # Process the request
                    $response = Invoke-Request -Request $request -ClientIdentity $clientIdentity
                }

                # Send response
                Write-PipeResponse -PipeServer $pipeServer -Response $response

                # Disconnect the client
                $pipeServer.Disconnect()
            }
            catch {
                Write-Warning "Error in service loop: $($_.Exception.Message)"
                Write-ErrorEvent -Message "Service loop error: $($_.Exception.Message)" -Exception $_.Exception
            }
            finally {
                if ($null -ne $pipeServer) {
                    try {
                        $pipeServer.Dispose()
                    }
                    catch { }
                }
            }

            if ($RunOnce) {
                Write-Verbose "RunOnce mode - exiting after single request"
                break
            }
        }
    }
    finally {
        Write-ServiceStoppedEvent -Reason "Service loop terminated"
    }
}

function Stop-Service {
    <#
    .SYNOPSIS
        Signals the service to stop.
    #>
    [CmdletBinding()]
    param()

    $script:Running = $false
    Write-Verbose "Stop signal received"
}

#endregion

#region Script Entry Point

# Handle Ctrl+C gracefully
$null = [Console]::TreatControlCAsInput = $false
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-Service
} | Out-Null

# Start the service
try {
    Start-ServiceLoop -RunOnce:$RunOnce -TimeoutSeconds $Timeout
}
catch {
    Write-Error "Fatal error in service: $($_.Exception.Message)"
    Write-ErrorEvent -Message "Fatal service error" -Exception $_.Exception
    exit 1
}

exit 0

#endregion
