#Requires -Version 5.1
<#
.SYNOPSIS
    Requests temporary administrator rights for the current user.

.DESCRIPTION
    The Add-TempAdmin cmdlet sends a request to the MakeMeAdminCLI service to
    grant temporary local administrator rights to the current user. The rights
    are automatically removed after the specified duration.

    This cmdlet communicates with the MakeMeAdminCLI service via named pipe.
    The service must be installed and running for this cmdlet to work.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

function Add-TempAdmin {
    <#
    .SYNOPSIS
        Requests temporary administrator rights for the current user.

    .DESCRIPTION
        Sends a request to the MakeMeAdminCLI service to add the current user
        to the local Administrators group for a specified duration. After the
        duration expires, the user is automatically removed from the group.

        The service validates that:
        - The user is allowed to request admin rights (based on AllowedUsers/DeniedUsers)
        - The requested duration is within configured limits
        - The request comes from the actual user (not impersonation)

    .PARAMETER DurationMinutes
        The duration in minutes for which admin rights should be granted.
        If not specified, uses the default duration from the service configuration.
        The value is clamped to the configured minimum and maximum limits.

    .PARAMETER Force
        If the user already has temporary admin rights, extend or reset the duration
        without prompting for confirmation.

    .OUTPUTS
        PSCustomObject with properties:
        - Success: Boolean indicating if the request was successful
        - Message: Descriptive message about the result
        - Username: The username that was granted/denied rights
        - ExpiresAt: DateTime when the rights will expire (if successful)
        - DurationMinutes: The actual duration granted (may differ from requested)

    .EXAMPLE
        Add-TempAdmin

        Requests temporary admin rights using the default duration.

    .EXAMPLE
        Add-TempAdmin -DurationMinutes 30

        Requests temporary admin rights for 30 minutes.

    .EXAMPLE
        Add-TempAdmin -DurationMinutes 60 -Force

        Requests 60 minutes of admin rights, extending any existing session
        without confirmation.

    .EXAMPLE
        $result = Add-TempAdmin -DurationMinutes 15
        if ($result.Success) {
            Write-Host "Admin rights granted until $($result.ExpiresAt)"
        }

        Captures the result for programmatic use.

    .LINK
        Remove-TempAdmin
        Get-TempAdminStatus
        Set-TempAdminConfig
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, 1440)]
        [int]$DurationMinutes = 0,

        [switch]$Force
    )

    begin {
        # Get current username
        $currentUser = Get-CurrentUsername
        Write-Verbose "Requesting admin rights for: $currentUser"

        # Check if service is running
        if (-not (Test-ServiceRunning)) {
            $errorResult = [PSCustomObject]@{
                Success = $false
                Message = "MakeMeAdminCLI service is not running. Run 'Install-MakeMeAdminCLI' as administrator to start the service."
                Username = $currentUser
                ExpiresAt = $null
                DurationMinutes = 0
            }
            Write-Error $errorResult.Message
            return $errorResult
        }
    }

    process {
        # Check current status first
        $statusRequest = @{
            action = "status"
            username = $currentUser
        }

        $statusResponse = Send-PipeRequest -Request $statusRequest

        if ($statusResponse -and $statusResponse.isAdmin -and $statusResponse.expiresAt) {
            $existingExpiry = [datetime]::Parse($statusResponse.expiresAt)

            if (-not $Force) {
                $confirmMessage = "You already have temporary admin rights (expires at $($existingExpiry.ToString('HH:mm:ss'))). Do you want to extend/reset the duration?"

                if (-not $PSCmdlet.ShouldProcess($currentUser, "Extend temporary admin rights")) {
                    Write-Warning "You already have temporary admin rights (expires at $($existingExpiry.ToString('HH:mm:ss'))). Use -Force to extend."
                    return [PSCustomObject]@{
                        Success = $false
                        Message = "Already elevated. Use -Force to extend."
                        Username = $currentUser
                        ExpiresAt = $existingExpiry
                        DurationMinutes = 0
                    }
                }
            }

            Write-Verbose "Extending/resetting existing admin rights."
        }

        # Build the add request
        $addRequest = @{
            action = "add"
            username = $currentUser
        }

        if ($DurationMinutes -gt 0) {
            $addRequest.duration = $DurationMinutes
        }

        Write-Verbose "Sending add request to service..."

        if ($PSCmdlet.ShouldProcess($currentUser, "Grant temporary admin rights")) {
            $response = Send-PipeRequest -Request $addRequest

            if ($null -eq $response) {
                return [PSCustomObject]@{
                    Success = $false
                    Message = "Failed to communicate with MakeMeAdminCLI service."
                    Username = $currentUser
                    ExpiresAt = $null
                    DurationMinutes = 0
                }
            }

            # Parse expiration time
            $expiresAt = $null
            $actualDuration = 0
            if ($response.expiresAt) {
                $expiresAt = [datetime]::Parse($response.expiresAt)
                $actualDuration = [math]::Round(($expiresAt - (Get-Date)).TotalMinutes)
            }

            # Create result object
            $result = [PSCustomObject]@{
                Success = [bool]$response.success
                Message = $response.message
                Username = $currentUser
                ExpiresAt = $expiresAt
                DurationMinutes = $actualDuration
            }

            # Output user-friendly message
            if ($result.Success) {
                Write-Host ""
                Write-Host "Temporary admin rights granted." -ForegroundColor Green
                Write-Host "Username   : $($result.Username)"
                Write-Host "Expires At : $($result.ExpiresAt.ToString('yyyy-MM-dd HH:mm:ss'))"
                Write-Host "Duration   : $($result.DurationMinutes) minutes"
                Write-Host ""
                Write-Host "Note: New processes will run with admin rights. Existing processes retain their current privileges." -ForegroundColor Yellow
            }
            else {
                # Provide specific error messages
                if ($response.message -like "*not authorized*" -or $response.message -like "*Access denied*") {
                    Write-Error "Your account is not authorized to request admin rights."
                }
                else {
                    Write-Error $response.message
                }
            }

            return $result
        }
        else {
            # WhatIf mode
            return [PSCustomObject]@{
                Success = $false
                Message = "WhatIf: Would request admin rights for $currentUser"
                Username = $currentUser
                ExpiresAt = $null
                DurationMinutes = $DurationMinutes
            }
        }
    }
}

# Export the function
Export-ModuleMember -Function 'Add-TempAdmin'
