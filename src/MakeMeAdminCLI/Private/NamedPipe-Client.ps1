#Requires -Version 5.1
<#
.SYNOPSIS
    Named pipe client helper functions for MakeMeAdminCLI.

.DESCRIPTION
    Provides functions for client-side communication with the MakeMeAdminCLI
    named pipe server. Handles connection, request/response, timeouts, and
    error handling for non-elevated client processes.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

function Connect-MakeMeAdminPipe {
    <#
    .SYNOPSIS
        Establishes a connection to the MakeMeAdminCLI named pipe server.

    .DESCRIPTION
        Creates a named pipe client connection to the MakeMeAdminCLI service.
        Handles connection timeouts and provides meaningful error messages
        when the service is not running.

    .PARAMETER PipeName
        The name of the named pipe to connect to. Defaults to the configured pipe name.

    .PARAMETER TimeoutMilliseconds
        The timeout in milliseconds for the connection attempt. Defaults to 5000.

    .OUTPUTS
        System.IO.Pipes.NamedPipeClientStream or $null on failure.

    .EXAMPLE
        $pipe = Connect-MakeMeAdminPipe
        if ($pipe) {
            # Use the pipe
            $pipe.Dispose()
        }
    #>
    [CmdletBinding()]
    [OutputType([System.IO.Pipes.NamedPipeClientStream])]
    param(
        [string]$PipeName,

        [int]$TimeoutMilliseconds = 5000
    )

    # Get pipe name from config if not specified
    if (-not $PipeName) {
        try {
            $config = Get-MakeMeAdminConfig
            $PipeName = $config.PipeName
        }
        catch {
            $PipeName = "MakeMeAdminCLI"
        }
    }

    try {
        # Create the named pipe client
        $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(
            ".",                                          # Server name (local)
            $PipeName,                                    # Pipe name
            [System.IO.Pipes.PipeDirection]::InOut,       # Direction
            [System.IO.Pipes.PipeOptions]::None           # Options
        )

        # Attempt to connect with timeout
        Write-Verbose "Connecting to named pipe '$PipeName'..."
        $pipeClient.Connect($TimeoutMilliseconds)
        $pipeClient.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Message

        Write-Verbose "Connected to named pipe successfully."
        return $pipeClient
    }
    catch [System.TimeoutException] {
        Write-Error "Connection timeout: MakeMeAdminCLI service is not responding. Is the service running?"
        return $null
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "MakeMeAdminCLI service is not running. Run 'Install-MakeMeAdminCLI' as administrator to start the service."
        return $null
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Access denied connecting to MakeMeAdminCLI service. You may not have permission to use this service."
        return $null
    }
    catch {
        Write-Error "Failed to connect to MakeMeAdminCLI service: $($_.Exception.Message)"
        return $null
    }
}

function Send-PipeRequest {
    <#
    .SYNOPSIS
        Sends a request to the MakeMeAdminCLI service via named pipe.

    .DESCRIPTION
        Sends a JSON-formatted request through the named pipe and returns
        the parsed JSON response. Handles serialization, timeouts, and errors.

    .PARAMETER Request
        A hashtable or PSCustomObject containing the request data.
        Expected format: @{ action = "add|remove|status"; duration = 15; username = "DOMAIN\user" }

    .PARAMETER TimeoutSeconds
        The timeout in seconds for the entire operation. Defaults to 30.

    .OUTPUTS
        PSCustomObject containing the response from the service, or $null on error.

    .EXAMPLE
        $response = Send-PipeRequest -Request @{ action = "add"; duration = 30 }
        if ($response.success) {
            Write-Host "Admin rights granted until $($response.expiresAt)"
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [object]$Request,

        [int]$TimeoutSeconds = 30
    )

    $pipeClient = $null
    $reader = $null
    $writer = $null

    try {
        # Connect to the pipe
        $pipeClient = Connect-MakeMeAdminPipe -TimeoutMilliseconds ($TimeoutSeconds * 1000)

        if ($null -eq $pipeClient) {
            return $null
        }

        # Create reader and writer
        $writer = New-Object System.IO.StreamWriter($pipeClient)
        $writer.AutoFlush = $true

        $reader = New-Object System.IO.StreamReader($pipeClient)

        # Serialize and send the request
        $jsonRequest = $Request | ConvertTo-Json -Compress
        Write-Verbose "Sending request: $jsonRequest"
        $writer.WriteLine($jsonRequest)

        # Read the response with timeout
        $readTask = $reader.ReadLineAsync()
        $completed = $readTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))

        if (-not $completed) {
            Write-Error "Response timeout: MakeMeAdminCLI service did not respond in time."
            return $null
        }

        $jsonResponse = $readTask.Result

        if ([string]::IsNullOrWhiteSpace($jsonResponse)) {
            Write-Error "Empty response received from MakeMeAdminCLI service."
            return $null
        }

        Write-Verbose "Received response: $jsonResponse"

        # Parse and return the response
        $response = $jsonResponse | ConvertFrom-Json
        return $response
    }
    catch {
        Write-Error "Error communicating with MakeMeAdminCLI service: $($_.Exception.Message)"
        return $null
    }
    finally {
        # Clean up resources
        if ($null -ne $reader) {
            try { $reader.Dispose() } catch { }
        }
        if ($null -ne $writer) {
            try { $writer.Dispose() } catch { }
        }
        if ($null -ne $pipeClient) {
            try { $pipeClient.Dispose() } catch { }
        }
    }
}

function Test-ServiceRunning {
    <#
    .SYNOPSIS
        Tests if the MakeMeAdminCLI service is running.

    .DESCRIPTION
        Attempts to connect to the named pipe to verify the service is available.
        This is a quick check that doesn't send any requests.

    .OUTPUTS
        Boolean indicating whether the service is available.

    .EXAMPLE
        if (Test-ServiceRunning) {
            Write-Host "Service is running"
        } else {
            Write-Host "Service is not running"
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $pipeClient = $null

    try {
        $config = Get-MakeMeAdminConfig
        $pipeName = $config.PipeName

        $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(
            ".",
            $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::None
        )

        # Quick connection test with short timeout
        $pipeClient.Connect(1000)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $pipeClient) {
            try { $pipeClient.Dispose() } catch { }
        }
    }
}

function Get-CurrentUsername {
    <#
    .SYNOPSIS
        Gets the current user's full username in DOMAIN\User format.

    .DESCRIPTION
        Returns the current Windows identity name, which is used for
        requests to the MakeMeAdminCLI service.

    .OUTPUTS
        String containing the username in DOMAIN\User format.

    .EXAMPLE
        $username = Get-CurrentUsername
        # Returns something like "CONTOSO\jdoe"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Test-IsElevated {
    <#
    .SYNOPSIS
        Tests if the current PowerShell session is running elevated (as admin).

    .DESCRIPTION
        Checks if the current process has administrator privileges.

    .OUTPUTS
        Boolean indicating whether the session is elevated.

    .EXAMPLE
        if (Test-IsElevated) {
            Write-Host "Running as administrator"
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Export module members (when dot-sourced from module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Connect-MakeMeAdminPipe',
        'Send-PipeRequest',
        'Test-ServiceRunning',
        'Get-CurrentUsername',
        'Test-IsElevated'
    )
}
