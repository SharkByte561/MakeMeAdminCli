#Requires -Version 5.1
<#
.SYNOPSIS
    Removes temporary administrator rights for the current user.

.DESCRIPTION
    The Remove-TempAdmin cmdlet sends a request to the MakeMeAdminCLI service to
    remove the current user from the local Administrators group immediately,
    instead of waiting for the scheduled expiration.

    This cmdlet communicates with the MakeMeAdminCLI service via named pipe.
    The service must be installed and running for this cmdlet to work.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

function Remove-TempAdmin {
    <#
    .SYNOPSIS
        Removes temporary administrator rights for the current user.

    .DESCRIPTION
        Sends a request to the MakeMeAdminCLI service to immediately remove the
        current user from the local Administrators group. This is useful when you
        want to relinquish admin rights before the scheduled expiration time.

        The service validates that:
        - The request comes from the actual user (not impersonation)
        - The user is currently in the Administrators group

    .PARAMETER Force
        Skip confirmation prompt before removing admin rights.

    .OUTPUTS
        PSCustomObject with properties:
        - Success: Boolean indicating if the removal was successful
        - Message: Descriptive message about the result
        - Username: The username that was processed

    .EXAMPLE
        Remove-TempAdmin

        Removes temporary admin rights after confirming with the user.

    .EXAMPLE
        Remove-TempAdmin -Force

        Removes temporary admin rights without confirmation.

    .EXAMPLE
        $result = Remove-TempAdmin -Force
        if ($result.Success) {
            Write-Host "Admin rights removed successfully"
        }

        Captures the result for programmatic use.

    .LINK
        Add-TempAdmin
        Get-TempAdminStatus
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [switch]$Force
    )

    begin {
        # Get current username
        $currentUser = Get-CurrentUsername
        Write-Verbose "Removing admin rights for: $currentUser"

        # Check if service is running
        if (-not (Test-ServiceRunning)) {
            $errorResult = [PSCustomObject]@{
                Success = $false
                Message = "MakeMeAdminCLI service is not running. Run 'Install-MakeMeAdminCLI' as administrator to start the service."
                Username = $currentUser
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

        if ($null -eq $statusResponse) {
            return [PSCustomObject]@{
                Success = $false
                Message = "Failed to communicate with MakeMeAdminCLI service."
                Username = $currentUser
            }
        }

        # Check if user has admin rights to remove
        if (-not $statusResponse.isAdmin) {
            Write-Warning "You do not currently have temporary admin rights."
            return [PSCustomObject]@{
                Success = $true
                Message = "You do not currently have temporary admin rights."
                Username = $currentUser
            }
        }

        # Confirm removal unless -Force is specified
        if (-not $Force) {
            $expiryInfo = ""
            if ($statusResponse.expiresAt) {
                $expiresAt = [datetime]::Parse($statusResponse.expiresAt)
                $remaining = $expiresAt - (Get-Date)
                $expiryInfo = " (would expire at $($expiresAt.ToString('HH:mm:ss')), $([math]::Floor($remaining.TotalMinutes)) minutes remaining)"
            }

            if (-not $PSCmdlet.ShouldProcess($currentUser, "Remove temporary admin rights$expiryInfo")) {
                return [PSCustomObject]@{
                    Success = $false
                    Message = "Removal cancelled by user."
                    Username = $currentUser
                }
            }
        }

        # Build the remove request
        $removeRequest = @{
            action = "remove"
            username = $currentUser
        }

        Write-Verbose "Sending remove request to service..."

        $response = Send-PipeRequest -Request $removeRequest

        if ($null -eq $response) {
            return [PSCustomObject]@{
                Success = $false
                Message = "Failed to communicate with MakeMeAdminCLI service."
                Username = $currentUser
            }
        }

        # Create result object
        $result = [PSCustomObject]@{
            Success = [bool]$response.success
            Message = $response.message
            Username = $currentUser
        }

        # Output user-friendly message
        if ($result.Success) {
            Write-Host ""
            Write-Host "Temporary admin rights removed." -ForegroundColor Green
            Write-Host "Username : $($result.Username)"
            Write-Host ""
            Write-Host "Note: Existing elevated processes will retain their privileges until closed." -ForegroundColor Yellow
        }
        else {
            Write-Error $response.message
        }

        return $result
    }
}

# Export the function
Export-ModuleMember -Function 'Remove-TempAdmin'
