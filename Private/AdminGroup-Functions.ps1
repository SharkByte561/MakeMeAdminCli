#Requires -Version 5.1
<#
.SYNOPSIS
    Administrator group management functions for MakeMeAdminCLI.

.DESCRIPTION
    Provides functions to add and remove users from the local Administrators group
    using the well-known SID S-1-5-32-544 for language independence.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0

    The well-known SID S-1-5-32-544 identifies the built-in Administrators group
    on any Windows system, regardless of the display language.
#>

# Well-known SID for the local Administrators group
$script:AdminGroupSID = "S-1-5-32-544"

function Get-LocalAdministratorsGroupName {
    <#
    .SYNOPSIS
        Gets the localized name of the local Administrators group.

    .DESCRIPTION
        Uses the well-known SID S-1-5-32-544 to resolve the local Administrators
        group name. This works on any Windows language version.

    .OUTPUTS
        String containing the localized name of the Administrators group.

    .EXAMPLE
        $groupName = Get-LocalAdministratorsGroupName
        # Returns "Administrators" on English systems, "Administratoren" on German, etc.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($script:AdminGroupSID)
        $account = $sid.Translate([System.Security.Principal.NTAccount])
        $fullName = $account.Value

        # Extract just the group name (remove BUILTIN\ or computer name prefix)
        if ($fullName -match '\\(.+)$') {
            return $Matches[1]
        }
        return $fullName
    }
    catch {
        throw "Failed to resolve Administrators group name from SID $script:AdminGroupSID : $($_.Exception.Message)"
    }
}

function Test-UserIsLocalAdmin {
    <#
    .SYNOPSIS
        Tests whether a user is currently a member of the local Administrators group.

    .DESCRIPTION
        Checks group membership using the localized Administrators group name
        resolved from the well-known SID.

    .PARAMETER Username
        The username to check, in DOMAIN\User or just User format.

    .OUTPUTS
        Boolean indicating whether the user is a member of the local Administrators group.

    .EXAMPLE
        Test-UserIsLocalAdmin -Username "DOMAIN\JohnDoe"
        Returns $true if the user is a local admin.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    try {
        $groupName = Get-LocalAdministratorsGroupName
        $members = Get-LocalGroupMember -Group $groupName -ErrorAction SilentlyContinue

        foreach ($member in $members) {
            # Compare both the full name and just the username part
            if ($member.Name -eq $Username) {
                return $true
            }
            # Also check if just the username part matches (for local accounts)
            $memberUsername = $member.Name
            if ($memberUsername -match '\\(.+)$') {
                $memberUsername = $Matches[1]
            }
            $checkUsername = $Username
            if ($checkUsername -match '\\(.+)$') {
                $checkUsername = $Matches[1]
            }
            if ($memberUsername -eq $checkUsername) {
                return $true
            }
        }
        return $false
    }
    catch {
        Write-Warning "Error checking group membership for '$Username': $($_.Exception.Message)"
        return $false
    }
}

function Add-UserToLocalAdmins {
    <#
    .SYNOPSIS
        Adds a user to the local Administrators group.

    .DESCRIPTION
        Adds the specified user to the local Administrators group. Uses the
        well-known SID for language independence. The function first checks
        if the user is already a member to avoid errors.

    .PARAMETER Username
        The username to add, in DOMAIN\User format.

    .PARAMETER SkipMembershipCheck
        If specified, skips the check for existing membership.

    .OUTPUTS
        PSCustomObject with Success (bool), AlreadyMember (bool), and Message (string) properties.

    .EXAMPLE
        $result = Add-UserToLocalAdmins -Username "DOMAIN\JohnDoe"
        if ($result.Success) {
            Write-Host "User added successfully"
        }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [switch]$SkipMembershipCheck
    )

    $result = [PSCustomObject]@{
        Success = $false
        AlreadyMember = $false
        Message = ""
    }

    try {
        $groupName = Get-LocalAdministratorsGroupName

        # Check if user is already a member
        if (-not $SkipMembershipCheck) {
            if (Test-UserIsLocalAdmin -Username $Username) {
                $result.AlreadyMember = $true
                $result.Success = $true
                $result.Message = "User '$Username' is already a member of the local Administrators group."
                Write-Verbose $result.Message
                return $result
            }
        }

        if ($PSCmdlet.ShouldProcess($Username, "Add to local Administrators group")) {
            # Try using Add-LocalGroupMember first (preferred method)
            try {
                Add-LocalGroupMember -Group $groupName -Member $Username -ErrorAction Stop
                $result.Success = $true
                $result.Message = "User '$Username' added to local Administrators group successfully."
            }
            catch {
                # Fallback to net localgroup command
                Write-Verbose "Add-LocalGroupMember failed, trying net localgroup: $($_.Exception.Message)"

                $netResult = & net localgroup "$groupName" "$Username" /add 2>&1
                $exitCode = $LASTEXITCODE

                if ($exitCode -eq 0) {
                    $result.Success = $true
                    $result.Message = "User '$Username' added to local Administrators group successfully (via net localgroup)."
                }
                elseif ($exitCode -eq 2 -or $netResult -match "already a member") {
                    # Error code 2 typically means already a member
                    $result.AlreadyMember = $true
                    $result.Success = $true
                    $result.Message = "User '$Username' is already a member of the local Administrators group."
                }
                else {
                    throw "net localgroup returned exit code $exitCode : $netResult"
                }
            }

            # Verify the user was actually added
            if ($result.Success -and -not $result.AlreadyMember) {
                Start-Sleep -Milliseconds 500  # Brief pause for group membership to propagate
                if (-not (Test-UserIsLocalAdmin -Username $Username)) {
                    Write-Warning "User '$Username' was added but membership could not be verified immediately."
                }
            }
        }
        else {
            $result.Message = "Operation cancelled by user (WhatIf mode)."
        }
    }
    catch {
        $result.Success = $false
        $result.Message = "Failed to add user '$Username' to local Administrators group: $($_.Exception.Message)"
        Write-Error $result.Message
    }

    return $result
}

function Remove-UserFromLocalAdmins {
    <#
    .SYNOPSIS
        Removes a user from the local Administrators group.

    .DESCRIPTION
        Removes the specified user from the local Administrators group. Uses the
        well-known SID for language independence. The function first checks
        if the user is actually a member.

    .PARAMETER Username
        The username to remove, in DOMAIN\User format.

    .PARAMETER SkipMembershipCheck
        If specified, skips the check for existing membership.

    .PARAMETER Force
        If specified, attempts removal even if the user doesn't appear to be a member.

    .OUTPUTS
        PSCustomObject with Success (bool), WasNotMember (bool), and Message (string) properties.

    .EXAMPLE
        $result = Remove-UserFromLocalAdmins -Username "DOMAIN\JohnDoe"
        if ($result.Success) {
            Write-Host "User removed successfully"
        }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [switch]$SkipMembershipCheck,

        [switch]$Force
    )

    $result = [PSCustomObject]@{
        Success = $false
        WasNotMember = $false
        Message = ""
    }

    try {
        $groupName = Get-LocalAdministratorsGroupName

        # Check if user is actually a member
        if (-not $SkipMembershipCheck -and -not $Force) {
            if (-not (Test-UserIsLocalAdmin -Username $Username)) {
                $result.WasNotMember = $true
                $result.Success = $true
                $result.Message = "User '$Username' is not a member of the local Administrators group."
                Write-Verbose $result.Message
                return $result
            }
        }

        if ($PSCmdlet.ShouldProcess($Username, "Remove from local Administrators group")) {
            # Try using Remove-LocalGroupMember first (preferred method)
            try {
                Remove-LocalGroupMember -Group $groupName -Member $Username -ErrorAction Stop
                $result.Success = $true
                $result.Message = "User '$Username' removed from local Administrators group successfully."
            }
            catch {
                # Fallback to net localgroup command
                Write-Verbose "Remove-LocalGroupMember failed, trying net localgroup: $($_.Exception.Message)"

                $netResult = & net localgroup "$groupName" "$Username" /delete 2>&1
                $exitCode = $LASTEXITCODE

                if ($exitCode -eq 0) {
                    $result.Success = $true
                    $result.Message = "User '$Username' removed from local Administrators group successfully (via net localgroup)."
                }
                elseif ($netResult -match "not.+member" -or $netResult -match "does not belong") {
                    $result.WasNotMember = $true
                    $result.Success = $true
                    $result.Message = "User '$Username' was not a member of the local Administrators group."
                }
                else {
                    throw "net localgroup returned exit code $exitCode : $netResult"
                }
            }

            # Verify the user was actually removed
            if ($result.Success -and -not $result.WasNotMember) {
                Start-Sleep -Milliseconds 500  # Brief pause for group membership to propagate
                if (Test-UserIsLocalAdmin -Username $Username) {
                    $result.Success = $false
                    $result.Message = "User '$Username' still appears to be a member after removal attempt."
                    Write-Warning $result.Message
                }
            }
        }
        else {
            $result.Message = "Operation cancelled by user (WhatIf mode)."
        }
    }
    catch {
        $result.Success = $false
        $result.Message = "Failed to remove user '$Username' from local Administrators group: $($_.Exception.Message)"
        Write-Error $result.Message
    }

    return $result
}

function Get-LocalAdminMembers {
    <#
    .SYNOPSIS
        Gets all members of the local Administrators group.

    .DESCRIPTION
        Returns a list of all users and groups that are members of the
        local Administrators group.

    .OUTPUTS
        Array of PSCustomObject with Name, SID, PrincipalSource, and ObjectClass properties.

    .EXAMPLE
        $admins = Get-LocalAdminMembers
        $admins | Format-Table Name, SID
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        $groupName = Get-LocalAdministratorsGroupName
        $members = Get-LocalGroupMember -Group $groupName -ErrorAction Stop

        $result = @()
        foreach ($member in $members) {
            $result += [PSCustomObject]@{
                Name = $member.Name
                SID = $member.SID.Value
                PrincipalSource = $member.PrincipalSource
                ObjectClass = $member.ObjectClass
            }
        }

        return $result
    }
    catch {
        Write-Error "Failed to get local Administrators group members: $($_.Exception.Message)"
        return @()
    }
}

function Get-UserSID {
    <#
    .SYNOPSIS
        Gets the Security Identifier (SID) for a username.

    .DESCRIPTION
        Resolves a username to its SID.

    .PARAMETER Username
        The username to resolve (DOMAIN\User or User format).

    .OUTPUTS
        String containing the SID, or $null if resolution fails.

    .EXAMPLE
        $sid = Get-UserSID -Username "DOMAIN\JohnDoe"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    try {
        # Handle different username formats
        $resolvedUsername = $Username

        # If it starts with .\ replace with computer name
        if ($resolvedUsername.StartsWith(".\")) {
            $resolvedUsername = "$env:COMPUTERNAME\" + $resolvedUsername.Substring(2)
        }

        $account = New-Object System.Security.Principal.NTAccount($resolvedUsername)
        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier])
        return $sid.Value
    }
    catch {
        Write-Verbose "Failed to resolve SID for '$Username': $($_.Exception.Message)"
        return $null
    }
}

function Get-UsernameFromSID {
    <#
    .SYNOPSIS
        Gets the username for a Security Identifier (SID).

    .DESCRIPTION
        Resolves a SID to its username.

    .PARAMETER SID
        The SID string to resolve.

    .OUTPUTS
        String containing the username (DOMAIN\User format), or $null if resolution fails.

    .EXAMPLE
        $username = Get-UsernameFromSID -SID "S-1-5-21-..."
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$SID
    )

    try {
        $sidObject = New-Object System.Security.Principal.SecurityIdentifier($SID)
        $account = $sidObject.Translate([System.Security.Principal.NTAccount])
        return $account.Value
    }
    catch {
        Write-Verbose "Failed to resolve username for SID '$SID': $($_.Exception.Message)"
        return $null
    }
}

# Export module members (when dot-sourced from module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-LocalAdministratorsGroupName',
        'Test-UserIsLocalAdmin',
        'Add-UserToLocalAdmins',
        'Remove-UserFromLocalAdmins',
        'Get-LocalAdminMembers',
        'Get-UserSID',
        'Get-UsernameFromSID'
    )

    Export-ModuleMember -Variable 'AdminGroupSID'
}
