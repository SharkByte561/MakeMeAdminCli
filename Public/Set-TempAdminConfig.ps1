#Requires -Version 5.1
<#
.SYNOPSIS
    Configures MakeMeAdminCLI settings.

.DESCRIPTION
    The Set-TempAdminConfig cmdlet allows administrators to view and modify
    the MakeMeAdminCLI service configuration settings including duration limits
    and user access controls.

    This cmdlet requires administrator privileges to modify settings.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

function Set-TempAdminConfig {
    <#
    .SYNOPSIS
        Configures MakeMeAdminCLI settings.

    .DESCRIPTION
        Views or modifies the MakeMeAdminCLI configuration settings. When called
        without parameters, displays the current configuration. When parameters
        are provided, updates the specified settings.

        This cmdlet requires administrator privileges to modify settings.

        Configuration settings:
        - DefaultDurationMinutes: Default duration when no value is specified
        - MaxDurationMinutes: Maximum allowed duration
        - MinDurationMinutes: Minimum allowed duration
        - AllowedUsers: List of users permitted to request admin rights
        - DeniedUsers: List of users blocked from requesting admin rights

    .PARAMETER DefaultDurationMinutes
        The default duration in minutes for temporary admin rights when the user
        does not specify a duration. Must be between MinDurationMinutes and
        MaxDurationMinutes.

    .PARAMETER MaxDurationMinutes
        The maximum duration in minutes that users can request. Valid range: 1-1440.

    .PARAMETER MinDurationMinutes
        The minimum duration in minutes that users can request. Valid range: 1-1440.

    .PARAMETER AllowedUsers
        An array of usernames, SIDs, or wildcard patterns that are allowed to
        request admin rights. If empty, all users are allowed (except those in
        DeniedUsers). Supports patterns like "DOMAIN\*" or "S-1-5-21-*".

    .PARAMETER DeniedUsers
        An array of usernames, SIDs, or wildcard patterns that are explicitly
        denied admin rights. DeniedUsers takes precedence over AllowedUsers.

    .PARAMETER AddAllowedUser
        Add a single user to the AllowedUsers list without replacing existing entries.

    .PARAMETER RemoveAllowedUser
        Remove a single user from the AllowedUsers list.

    .PARAMETER AddDeniedUser
        Add a single user to the DeniedUsers list without replacing existing entries.

    .PARAMETER RemoveDeniedUser
        Remove a single user from the DeniedUsers list.

    .OUTPUTS
        PSCustomObject containing the current (or updated) configuration.

    .EXAMPLE
        Set-TempAdminConfig

        Displays the current configuration without making changes.

    .EXAMPLE
        Set-TempAdminConfig -DefaultDurationMinutes 30

        Sets the default duration to 30 minutes.

    .EXAMPLE
        Set-TempAdminConfig -MaxDurationMinutes 120 -MinDurationMinutes 5

        Sets the maximum duration to 120 minutes and minimum to 5 minutes.

    .EXAMPLE
        Set-TempAdminConfig -AllowedUsers @("DOMAIN\AdminGroup", "DOMAIN\JohnDoe")

        Restricts admin rights requests to only the specified users.

    .EXAMPLE
        Set-TempAdminConfig -AddAllowedUser "DOMAIN\NewUser"

        Adds a user to the allowed list without clearing existing entries.

    .EXAMPLE
        Set-TempAdminConfig -DeniedUsers @("DOMAIN\GuestAccount")

        Blocks the specified user from requesting admin rights.

    .EXAMPLE
        Set-TempAdminConfig -AllowedUsers @() -DeniedUsers @()

        Clears both allow and deny lists (allows all users).

    .LINK
        Add-TempAdmin
        Get-TempAdminStatus
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'View')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Modify')]
        [ValidateRange(1, 1440)]
        [int]$DefaultDurationMinutes,

        [Parameter(ParameterSetName = 'Modify')]
        [ValidateRange(1, 1440)]
        [int]$MaxDurationMinutes,

        [Parameter(ParameterSetName = 'Modify')]
        [ValidateRange(1, 1440)]
        [int]$MinDurationMinutes,

        [Parameter(ParameterSetName = 'Modify')]
        [string[]]$AllowedUsers,

        [Parameter(ParameterSetName = 'Modify')]
        [string[]]$DeniedUsers,

        [Parameter(ParameterSetName = 'AddUser')]
        [string]$AddAllowedUser,

        [Parameter(ParameterSetName = 'AddUser')]
        [string]$RemoveAllowedUser,

        [Parameter(ParameterSetName = 'AddUser')]
        [string]$AddDeniedUser,

        [Parameter(ParameterSetName = 'AddUser')]
        [string]$RemoveDeniedUser
    )

    begin {
        # Determine if any modifications are being requested
        $isModifying = $PSCmdlet.ParameterSetName -ne 'View'

        # Check for elevation if modifying
        if ($isModifying -and -not (Test-IsElevated)) {
            Write-Error "Administrator privileges are required to modify MakeMeAdminCLI configuration. Run PowerShell as Administrator."
            return
        }
    }

    process {
        try {
            # Get current configuration
            $config = Get-MakeMeAdminConfig

            # If no modification parameters provided, just display current config
            if (-not $isModifying) {
                Write-Host ""
                Write-Host "MakeMeAdminCLI Configuration" -ForegroundColor Cyan
                Write-Host "-" * 40

                Write-Host ""
                Write-Host "Duration Settings:" -ForegroundColor Yellow
                Write-Host "  Default Duration : $($config.DefaultDurationMinutes) minutes"
                Write-Host "  Maximum Duration : $($config.MaxDurationMinutes) minutes"
                Write-Host "  Minimum Duration : $($config.MinDurationMinutes) minutes"

                Write-Host ""
                Write-Host "Access Control:" -ForegroundColor Yellow

                if ($config.AllowedUsers -and $config.AllowedUsers.Count -gt 0) {
                    Write-Host "  Allowed Users    : "
                    foreach ($user in $config.AllowedUsers) {
                        Write-Host "                     - $user"
                    }
                }
                else {
                    Write-Host "  Allowed Users    : (all users allowed)"
                }

                if ($config.DeniedUsers -and $config.DeniedUsers.Count -gt 0) {
                    Write-Host "  Denied Users     : "
                    foreach ($user in $config.DeniedUsers) {
                        Write-Host "                     - $user"
                    }
                }
                else {
                    Write-Host "  Denied Users     : (none)"
                }

                Write-Host ""
                Write-Host "Service Settings:" -ForegroundColor Yellow
                Write-Host "  Pipe Name        : $($config.PipeName)"
                Write-Host "  Event Log Source : $($config.EventLogSource)"
                Write-Host "  Task Path        : $($config.TaskPath)"
                Write-Host "  State File       : $($config.StateFilePath)"
                Write-Host ""

                return [PSCustomObject]@{
                    DefaultDurationMinutes = $config.DefaultDurationMinutes
                    MaxDurationMinutes = $config.MaxDurationMinutes
                    MinDurationMinutes = $config.MinDurationMinutes
                    AllowedUsers = @($config.AllowedUsers)
                    DeniedUsers = @($config.DeniedUsers)
                    PipeName = $config.PipeName
                    EventLogSource = $config.EventLogSource
                    TaskPath = $config.TaskPath
                    StateFilePath = $config.StateFilePath
                }
            }

            # Handle add/remove user operations
            if ($PSCmdlet.ParameterSetName -eq 'AddUser') {
                $allowedList = [System.Collections.ArrayList]@($config.AllowedUsers)
                $deniedList = [System.Collections.ArrayList]@($config.DeniedUsers)

                if ($AddAllowedUser) {
                    if ($allowedList -notcontains $AddAllowedUser) {
                        $allowedList.Add($AddAllowedUser) | Out-Null
                        Write-Verbose "Added '$AddAllowedUser' to AllowedUsers"
                    }
                    else {
                        Write-Warning "'$AddAllowedUser' is already in AllowedUsers"
                    }
                }

                if ($RemoveAllowedUser) {
                    if ($allowedList -contains $RemoveAllowedUser) {
                        $allowedList.Remove($RemoveAllowedUser) | Out-Null
                        Write-Verbose "Removed '$RemoveAllowedUser' from AllowedUsers"
                    }
                    else {
                        Write-Warning "'$RemoveAllowedUser' is not in AllowedUsers"
                    }
                }

                if ($AddDeniedUser) {
                    if ($deniedList -notcontains $AddDeniedUser) {
                        $deniedList.Add($AddDeniedUser) | Out-Null
                        Write-Verbose "Added '$AddDeniedUser' to DeniedUsers"
                    }
                    else {
                        Write-Warning "'$AddDeniedUser' is already in DeniedUsers"
                    }
                }

                if ($RemoveDeniedUser) {
                    if ($deniedList -contains $RemoveDeniedUser) {
                        $deniedList.Remove($RemoveDeniedUser) | Out-Null
                        Write-Verbose "Removed '$RemoveDeniedUser' from DeniedUsers"
                    }
                    else {
                        Write-Warning "'$RemoveDeniedUser' is not in DeniedUsers"
                    }
                }

                $AllowedUsers = $allowedList.ToArray()
                $DeniedUsers = $deniedList.ToArray()
            }

            # Build update parameters
            $updateParams = @{}

            if ($PSBoundParameters.ContainsKey('DefaultDurationMinutes') -or $PSCmdlet.ParameterSetName -eq 'AddUser') {
                if ($PSBoundParameters.ContainsKey('DefaultDurationMinutes')) {
                    $updateParams['DefaultDurationMinutes'] = $DefaultDurationMinutes
                }
            }

            if ($PSBoundParameters.ContainsKey('MaxDurationMinutes')) {
                $updateParams['MaxDurationMinutes'] = $MaxDurationMinutes
            }

            if ($PSBoundParameters.ContainsKey('MinDurationMinutes')) {
                $updateParams['MinDurationMinutes'] = $MinDurationMinutes
            }

            if ($PSBoundParameters.ContainsKey('AllowedUsers') -or $PSCmdlet.ParameterSetName -eq 'AddUser') {
                if ($null -ne $AllowedUsers) {
                    $updateParams['AllowedUsers'] = $AllowedUsers
                }
            }

            if ($PSBoundParameters.ContainsKey('DeniedUsers') -or $PSCmdlet.ParameterSetName -eq 'AddUser') {
                if ($null -ne $DeniedUsers) {
                    $updateParams['DeniedUsers'] = $DeniedUsers
                }
            }

            # Validate the configuration before saving
            $newConfig = @{
                DefaultDurationMinutes = if ($updateParams.ContainsKey('DefaultDurationMinutes')) { $updateParams['DefaultDurationMinutes'] } else { $config.DefaultDurationMinutes }
                MaxDurationMinutes = if ($updateParams.ContainsKey('MaxDurationMinutes')) { $updateParams['MaxDurationMinutes'] } else { $config.MaxDurationMinutes }
                MinDurationMinutes = if ($updateParams.ContainsKey('MinDurationMinutes')) { $updateParams['MinDurationMinutes'] } else { $config.MinDurationMinutes }
            }

            # Validate duration constraints
            if ($newConfig.MinDurationMinutes -gt $newConfig.MaxDurationMinutes) {
                Write-Error "MinDurationMinutes ($($newConfig.MinDurationMinutes)) cannot be greater than MaxDurationMinutes ($($newConfig.MaxDurationMinutes))"
                return
            }

            if ($newConfig.DefaultDurationMinutes -lt $newConfig.MinDurationMinutes) {
                Write-Error "DefaultDurationMinutes ($($newConfig.DefaultDurationMinutes)) cannot be less than MinDurationMinutes ($($newConfig.MinDurationMinutes))"
                return
            }

            if ($newConfig.DefaultDurationMinutes -gt $newConfig.MaxDurationMinutes) {
                Write-Error "DefaultDurationMinutes ($($newConfig.DefaultDurationMinutes)) cannot be greater than MaxDurationMinutes ($($newConfig.MaxDurationMinutes))"
                return
            }

            # Apply the changes
            if ($updateParams.Count -gt 0) {
                $changeDescription = ($updateParams.Keys -join ", ")

                if ($PSCmdlet.ShouldProcess("MakeMeAdminCLI configuration", "Update settings: $changeDescription")) {
                    Set-MakeMeAdminConfig @updateParams

                    Write-Host ""
                    Write-Host "Configuration updated successfully." -ForegroundColor Green

                    # Display the updated configuration
                    $updatedConfig = Get-MakeMeAdminConfig

                    Write-Host ""
                    Write-Host "Updated Configuration:" -ForegroundColor Cyan
                    Write-Host "  Default Duration : $($updatedConfig.DefaultDurationMinutes) minutes"
                    Write-Host "  Maximum Duration : $($updatedConfig.MaxDurationMinutes) minutes"
                    Write-Host "  Minimum Duration : $($updatedConfig.MinDurationMinutes) minutes"

                    if ($updatedConfig.AllowedUsers -and $updatedConfig.AllowedUsers.Count -gt 0) {
                        Write-Host "  Allowed Users    : $($updatedConfig.AllowedUsers -join ', ')"
                    }
                    else {
                        Write-Host "  Allowed Users    : (all users allowed)"
                    }

                    if ($updatedConfig.DeniedUsers -and $updatedConfig.DeniedUsers.Count -gt 0) {
                        Write-Host "  Denied Users     : $($updatedConfig.DeniedUsers -join ', ')"
                    }
                    else {
                        Write-Host "  Denied Users     : (none)"
                    }
                    Write-Host ""

                    Write-Host "Note: Service may need to be restarted for some changes to take effect." -ForegroundColor Yellow
                    Write-Host ""

                    return [PSCustomObject]@{
                        DefaultDurationMinutes = $updatedConfig.DefaultDurationMinutes
                        MaxDurationMinutes = $updatedConfig.MaxDurationMinutes
                        MinDurationMinutes = $updatedConfig.MinDurationMinutes
                        AllowedUsers = @($updatedConfig.AllowedUsers)
                        DeniedUsers = @($updatedConfig.DeniedUsers)
                        PipeName = $updatedConfig.PipeName
                        EventLogSource = $updatedConfig.EventLogSource
                        TaskPath = $updatedConfig.TaskPath
                        StateFilePath = $updatedConfig.StateFilePath
                    }
                }
            }
        }
        catch {
            Write-Error "Failed to update configuration: $($_.Exception.Message)"
        }
    }
}

# Export the function
Export-ModuleMember -Function 'Set-TempAdminConfig'
