#Requires -Version 5.1
<#
.SYNOPSIS
    Gets the current temporary admin status for the user.

.DESCRIPTION
    The Get-TempAdminStatus cmdlet queries the MakeMeAdminCLI service to
    check if the current user has temporary administrator rights and
    displays the remaining time if elevated.

    This cmdlet communicates with the MakeMeAdminCLI service via named pipe.
    The service must be installed and running for this cmdlet to work.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

function Get-TempAdminStatus {
    <#
    .SYNOPSIS
        Gets the current temporary admin status for the user.

    .DESCRIPTION
        Queries the MakeMeAdminCLI service to determine the current elevation
        status of the user. If the user has temporary admin rights, displays
        the expiration time and remaining duration.

        With the -All parameter (requires elevation), displays status for all
        users who currently have temporary admin rights.

    .PARAMETER All
        Show status for all elevated users. Requires administrator privileges.

    .OUTPUTS
        PSCustomObject with properties:
        - Status: "Elevated" or "Not Elevated"
        - Username: The username being queried
        - IsAdmin: Boolean indicating current admin group membership
        - ExpiresAt: DateTime when rights will expire (if elevated)
        - Remaining: TimeSpan of remaining time (if elevated)
        - GrantedAt: DateTime when rights were granted (if available)

        When using -All, returns an array of objects for all elevated users.

    .EXAMPLE
        Get-TempAdminStatus

        Shows the current user's elevation status.

    .EXAMPLE
        Get-TempAdminStatus -All

        Shows all users with temporary admin rights (requires elevation).

    .EXAMPLE
        $status = Get-TempAdminStatus
        if ($status.Status -eq "Elevated") {
            Write-Host "Time remaining: $($status.Remaining.TotalMinutes) minutes"
        }

        Programmatically check elevation status.

    .LINK
        Add-TempAdmin
        Remove-TempAdmin
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$All
    )

    begin {
        # Get current username
        $currentUser = Get-CurrentUsername
        Write-Verbose "Checking admin status for: $currentUser"

        # Check if service is running
        if (-not (Test-ServiceRunning)) {
            $errorResult = [PSCustomObject]@{
                Status = "Unknown"
                Username = $currentUser
                IsAdmin = $false
                ExpiresAt = $null
                Remaining = $null
                GrantedAt = $null
                Message = "MakeMeAdminCLI service is not running."
            }
            Write-Error "MakeMeAdminCLI service is not running. Run 'Install-MakeMeAdminCLI' as administrator to start the service."
            return $errorResult
        }
    }

    process {
        if ($All) {
            # Check if running elevated
            if (-not (Test-IsElevated)) {
                Write-Error "The -All parameter requires administrator privileges. Run PowerShell as Administrator."
                return [PSCustomObject]@{
                    Status = "Error"
                    Message = "Administrator privileges required for -All parameter."
                    Username = $currentUser
                    IsAdmin = $false
                    ExpiresAt = $null
                    Remaining = $null
                    GrantedAt = $null
                }
            }

            # Get state file directly for all users (requires admin access)
            return Get-AllUsersStatus
        }

        # Query status for current user
        $statusRequest = @{
            action = "status"
            username = $currentUser
        }

        Write-Verbose "Sending status request to service..."

        $response = Send-PipeRequest -Request $statusRequest

        if ($null -eq $response) {
            return [PSCustomObject]@{
                Status = "Unknown"
                Username = $currentUser
                IsAdmin = $false
                ExpiresAt = $null
                Remaining = $null
                GrantedAt = $null
                Message = "Failed to communicate with MakeMeAdminCLI service."
            }
        }

        # Parse response and build result
        $isAdmin = [bool]$response.isAdmin
        $expiresAt = $null
        $grantedAt = $null
        $remaining = $null
        $status = "Not Elevated"

        if ($response.expiresAt) {
            $expiresAt = [datetime]::Parse($response.expiresAt)
            $remaining = $expiresAt - (Get-Date)

            # Check if already expired
            if ($remaining.TotalSeconds -le 0) {
                $status = "Expired"
                $remaining = [TimeSpan]::Zero
            }
            else {
                $status = "Elevated"
            }
        }
        elseif ($isAdmin) {
            $status = "Elevated (not tracked)"
        }

        if ($response.grantedAt) {
            $grantedAt = [datetime]::Parse($response.grantedAt)
        }

        $result = [PSCustomObject]@{
            Status = $status
            Username = $currentUser
            IsAdmin = $isAdmin
            ExpiresAt = $expiresAt
            Remaining = $remaining
            GrantedAt = $grantedAt
            Message = $response.message
        }

        # Display formatted output
        Write-Host ""
        if ($status -eq "Elevated") {
            Write-Host "Status     : " -NoNewline
            Write-Host "Elevated" -ForegroundColor Green
            Write-Host "Username   : $($result.Username)"
            Write-Host "Expires At : $($result.ExpiresAt.ToString('yyyy-MM-dd HH:mm:ss'))"
            Write-Host "Remaining  : $([math]::Floor($result.Remaining.TotalMinutes)) minutes $($result.Remaining.Seconds) seconds"

            if ($result.GrantedAt) {
                Write-Host "Granted At : $($result.GrantedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
            }
        }
        elseif ($status -eq "Elevated (not tracked)") {
            Write-Host "Status     : " -NoNewline
            Write-Host "Elevated (not tracked by MakeMeAdminCLI)" -ForegroundColor Yellow
            Write-Host "Username   : $($result.Username)"
            Write-Host ""
            Write-Host "You have admin rights but they were not granted by MakeMeAdminCLI." -ForegroundColor Yellow
        }
        elseif ($status -eq "Expired") {
            Write-Host "Status     : " -NoNewline
            Write-Host "Expired" -ForegroundColor Yellow
            Write-Host "Username   : $($result.Username)"
            Write-Host ""
            Write-Host "Your temporary admin rights have expired." -ForegroundColor Yellow
        }
        else {
            Write-Host "Status     : " -NoNewline
            Write-Host "Not Elevated" -ForegroundColor Cyan
            Write-Host "Username   : $($result.Username)"
            Write-Host ""
            Write-Host "You do not currently have temporary admin rights." -ForegroundColor Cyan
            Write-Host "Use 'Add-TempAdmin' to request temporary elevation." -ForegroundColor Gray
        }
        Write-Host ""

        return $result
    }
}

function Get-AllUsersStatus {
    <#
    .SYNOPSIS
        Gets status for all users with temporary admin rights.

    .DESCRIPTION
        Reads the state file directly to get information about all users
        currently tracked as having temporary admin rights.
        This function requires administrator privileges.

    .OUTPUTS
        Array of PSCustomObject with status information for each user.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        $config = Get-MakeMeAdminConfig
        $stateFilePath = $config.StateFilePath

        if (-not $stateFilePath) {
            $stateFilePath = Join-Path $env:ProgramData "MakeMeAdminCLI\state.json"
        }

        if (-not (Test-Path $stateFilePath)) {
            Write-Host ""
            Write-Host "No users currently have temporary admin rights." -ForegroundColor Cyan
            Write-Host ""
            return @()
        }

        $stateContent = Get-Content -Path $stateFilePath -Raw -ErrorAction Stop
        $state = $stateContent | ConvertFrom-Json

        if (-not $state.ActiveUsers -or $state.ActiveUsers.Count -eq 0) {
            Write-Host ""
            Write-Host "No users currently have temporary admin rights." -ForegroundColor Cyan
            Write-Host ""
            return @()
        }

        $results = @()
        $now = Get-Date

        foreach ($user in $state.ActiveUsers) {
            $expiresAt = [datetime]::Parse($user.ExpiresAt)
            $grantedAt = if ($user.GrantedAt) { [datetime]::Parse($user.GrantedAt) } else { $null }
            $remaining = $expiresAt - $now

            $status = if ($remaining.TotalSeconds -gt 0) { "Elevated" } else { "Expired" }

            $results += [PSCustomObject]@{
                Status = $status
                Username = $user.Username
                IsAdmin = $true
                ExpiresAt = $expiresAt
                Remaining = if ($remaining.TotalSeconds -gt 0) { $remaining } else { [TimeSpan]::Zero }
                GrantedAt = $grantedAt
                TaskName = $user.TaskName
            }
        }

        # Display formatted table
        Write-Host ""
        Write-Host "Users with Temporary Admin Rights:" -ForegroundColor Cyan
        Write-Host "-" * 80

        $results | Format-Table -Property @(
            @{Name = 'Status'; Expression = { $_.Status }; Width = 10 }
            @{Name = 'Username'; Expression = { $_.Username }; Width = 30 }
            @{Name = 'Expires At'; Expression = { $_.ExpiresAt.ToString('yyyy-MM-dd HH:mm:ss') }; Width = 20 }
            @{Name = 'Remaining'; Expression = {
                    if ($_.Remaining.TotalSeconds -gt 0) {
                        "$([math]::Floor($_.Remaining.TotalMinutes))m $($_.Remaining.Seconds)s"
                    }
                    else {
                        "Expired"
                    }
                }; Width = 15
            }
        ) -AutoSize

        return $results
    }
    catch {
        Write-Error "Failed to read state file: $($_.Exception.Message)"
        return @()
    }
}

# Export the function
Export-ModuleMember -Function 'Get-TempAdminStatus'
