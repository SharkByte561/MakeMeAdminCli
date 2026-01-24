#Requires -Version 5.1
<#
.SYNOPSIS
    Configuration management functions for MakeMeAdminCLI.

.DESCRIPTION
    Provides functions to read, validate, and manage configuration settings
    from the config.json file stored in the module directory.

.NOTES
    Author: MakeMeAdminCLI
    Version: 1.0.0
#>

# Module-level variables
# Only set ModuleRoot if not already set by the parent module (psm1)
if (-not $script:ModuleRoot -or -not (Test-Path $script:ModuleRoot)) {
    # When running standalone (e.g., from Service-Main.ps1), determine path from script location
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path (Join-Path $script:ModuleRoot "config.json"))) {
        # Fallback to installed module location
        $script:ModuleRoot = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\MakeMeAdminCLI"
    }
}
$script:ConfigFilePath = Join-Path $script:ModuleRoot "config.json"
$script:DefaultStateFolder = Join-Path $env:ProgramData "MakeMeAdminCLI"

# Default configuration values
$script:DefaultConfig = @{
    DefaultDurationMinutes = 15
    MaxDurationMinutes = 60
    MinDurationMinutes = 1
    EventLogSource = "MakeMeAdminCLI"
    AllowedUsers = @()
    DeniedUsers = @()
    PipeName = "MakeMeAdminCLI"
    TaskPath = "\Microsoft\Windows\MakeMeAdminCLI"
    StateFilePath = $null
}

function Get-MakeMeAdminConfig {
    <#
    .SYNOPSIS
        Retrieves the current configuration settings.

    .DESCRIPTION
        Reads the configuration from config.json and returns it as a PowerShell object.
        If the configuration file doesn't exist or is invalid, returns default values.

    .OUTPUTS
        PSCustomObject containing the configuration settings.

    .EXAMPLE
        $config = Get-MakeMeAdminConfig
        Write-Host "Default duration: $($config.DefaultDurationMinutes) minutes"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        if (Test-Path $script:ConfigFilePath) {
            $jsonContent = Get-Content -Path $script:ConfigFilePath -Raw -ErrorAction Stop
            $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop

            # Merge with defaults to ensure all properties exist
            $result = @{}
            foreach ($key in $script:DefaultConfig.Keys) {
                if ($null -ne $config.$key) {
                    $result[$key] = $config.$key
                } else {
                    $result[$key] = $script:DefaultConfig[$key]
                }
            }

            # Set default state file path if not specified
            if (-not $result.StateFilePath) {
                $result.StateFilePath = Join-Path $script:DefaultStateFolder "state.json"
            }

            return [PSCustomObject]$result
        } else {
            Write-Warning "Configuration file not found at '$script:ConfigFilePath'. Using defaults."
            $result = $script:DefaultConfig.Clone()
            $result.StateFilePath = Join-Path $script:DefaultStateFolder "state.json"
            return [PSCustomObject]$result
        }
    }
    catch {
        Write-Warning "Error reading configuration: $($_.Exception.Message). Using defaults."
        $result = $script:DefaultConfig.Clone()
        $result.StateFilePath = Join-Path $script:DefaultStateFolder "state.json"
        return [PSCustomObject]$result
    }
}

function Set-MakeMeAdminConfig {
    <#
    .SYNOPSIS
        Updates the configuration settings.

    .DESCRIPTION
        Modifies the config.json file with the provided settings.
        Only updates the settings that are provided; other settings remain unchanged.

    .PARAMETER DefaultDurationMinutes
        The default duration for temporary admin rights in minutes.

    .PARAMETER MaxDurationMinutes
        The maximum allowed duration in minutes.

    .PARAMETER MinDurationMinutes
        The minimum allowed duration in minutes.

    .PARAMETER AllowedUsers
        Array of usernames or SIDs that are allowed to request admin rights.
        Empty array means all users are allowed.

    .PARAMETER DeniedUsers
        Array of usernames or SIDs that are denied admin rights.

    .EXAMPLE
        Set-MakeMeAdminConfig -DefaultDurationMinutes 30 -MaxDurationMinutes 120
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateRange(1, 1440)]
        [int]$DefaultDurationMinutes,

        [ValidateRange(1, 1440)]
        [int]$MaxDurationMinutes,

        [ValidateRange(1, 1440)]
        [int]$MinDurationMinutes,

        [string[]]$AllowedUsers,

        [string[]]$DeniedUsers
    )

    try {
        # Get current config
        $config = Get-MakeMeAdminConfig
        $configHash = @{
            DefaultDurationMinutes = $config.DefaultDurationMinutes
            MaxDurationMinutes = $config.MaxDurationMinutes
            MinDurationMinutes = $config.MinDurationMinutes
            EventLogSource = $config.EventLogSource
            AllowedUsers = @($config.AllowedUsers)
            DeniedUsers = @($config.DeniedUsers)
            PipeName = $config.PipeName
            TaskPath = $config.TaskPath
            StateFilePath = $config.StateFilePath
        }

        # Update with provided values
        if ($PSBoundParameters.ContainsKey('DefaultDurationMinutes')) {
            $configHash.DefaultDurationMinutes = $DefaultDurationMinutes
        }
        if ($PSBoundParameters.ContainsKey('MaxDurationMinutes')) {
            $configHash.MaxDurationMinutes = $MaxDurationMinutes
        }
        if ($PSBoundParameters.ContainsKey('MinDurationMinutes')) {
            $configHash.MinDurationMinutes = $MinDurationMinutes
        }
        if ($PSBoundParameters.ContainsKey('AllowedUsers')) {
            $configHash.AllowedUsers = $AllowedUsers
        }
        if ($PSBoundParameters.ContainsKey('DeniedUsers')) {
            $configHash.DeniedUsers = $DeniedUsers
        }

        # Validate configuration
        if ($configHash.MinDurationMinutes -gt $configHash.MaxDurationMinutes) {
            throw "MinDurationMinutes ($($configHash.MinDurationMinutes)) cannot be greater than MaxDurationMinutes ($($configHash.MaxDurationMinutes))"
        }
        if ($configHash.DefaultDurationMinutes -lt $configHash.MinDurationMinutes -or
            $configHash.DefaultDurationMinutes -gt $configHash.MaxDurationMinutes) {
            throw "DefaultDurationMinutes ($($configHash.DefaultDurationMinutes)) must be between MinDurationMinutes ($($configHash.MinDurationMinutes)) and MaxDurationMinutes ($($configHash.MaxDurationMinutes))"
        }

        if ($PSCmdlet.ShouldProcess($script:ConfigFilePath, "Update configuration")) {
            $jsonContent = $configHash | ConvertTo-Json -Depth 10
            Set-Content -Path $script:ConfigFilePath -Value $jsonContent -Encoding UTF8 -Force
            Write-Verbose "Configuration saved to '$script:ConfigFilePath'"
        }
    }
    catch {
        throw "Failed to save configuration: $($_.Exception.Message)"
    }
}

function Test-MakeMeAdminConfig {
    <#
    .SYNOPSIS
        Validates the current configuration.

    .DESCRIPTION
        Checks that all configuration values are valid and returns a validation result.

    .OUTPUTS
        PSCustomObject with IsValid (bool) and Errors (array) properties.

    .EXAMPLE
        $result = Test-MakeMeAdminConfig
        if (-not $result.IsValid) {
            $result.Errors | ForEach-Object { Write-Error $_ }
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $errors = @()
    $config = Get-MakeMeAdminConfig

    # Validate duration settings
    if ($config.MinDurationMinutes -lt 1) {
        $errors += "MinDurationMinutes must be at least 1"
    }
    if ($config.MaxDurationMinutes -lt 1) {
        $errors += "MaxDurationMinutes must be at least 1"
    }
    if ($config.MinDurationMinutes -gt $config.MaxDurationMinutes) {
        $errors += "MinDurationMinutes cannot exceed MaxDurationMinutes"
    }
    if ($config.DefaultDurationMinutes -lt $config.MinDurationMinutes) {
        $errors += "DefaultDurationMinutes cannot be less than MinDurationMinutes"
    }
    if ($config.DefaultDurationMinutes -gt $config.MaxDurationMinutes) {
        $errors += "DefaultDurationMinutes cannot exceed MaxDurationMinutes"
    }

    # Validate event log source
    if ([string]::IsNullOrWhiteSpace($config.EventLogSource)) {
        $errors += "EventLogSource cannot be empty"
    }

    # Validate pipe name
    if ([string]::IsNullOrWhiteSpace($config.PipeName)) {
        $errors += "PipeName cannot be empty"
    }

    # Validate task path
    if ([string]::IsNullOrWhiteSpace($config.TaskPath)) {
        $errors += "TaskPath cannot be empty"
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
        Config = $config
    }
}

function Get-StateFilePath {
    <#
    .SYNOPSIS
        Gets the path to the state file, ensuring the directory exists.

    .DESCRIPTION
        Returns the configured state file path and creates the parent directory if needed.

    .OUTPUTS
        String containing the full path to the state file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $config = Get-MakeMeAdminConfig
    $stateFilePath = $config.StateFilePath

    if (-not $stateFilePath) {
        $stateFilePath = Join-Path $script:DefaultStateFolder "state.json"
    }

    # Ensure the directory exists
    $stateFolder = Split-Path -Parent $stateFilePath
    if (-not (Test-Path $stateFolder)) {
        try {
            New-Item -ItemType Directory -Path $stateFolder -Force | Out-Null
        }
        catch {
            Write-Warning "Failed to create state folder '$stateFolder': $($_.Exception.Message)"
        }
    }

    return $stateFilePath
}

function Test-UserAllowed {
    <#
    .SYNOPSIS
        Checks if a user is allowed to request admin rights based on configuration.

    .DESCRIPTION
        Evaluates the AllowedUsers and DeniedUsers lists to determine if a user
        can request temporary admin rights.

    .PARAMETER Username
        The username to check (in DOMAIN\User or User format).

    .PARAMETER UserSID
        The security identifier of the user.

    .OUTPUTS
        Boolean indicating whether the user is allowed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [string]$UserSID
    )

    $config = Get-MakeMeAdminConfig

    # Check denied list first (takes precedence)
    if ($config.DeniedUsers -and $config.DeniedUsers.Count -gt 0) {
        foreach ($denied in $config.DeniedUsers) {
            if ($Username -like $denied -or $Username -eq $denied) {
                return $false
            }
            if ($UserSID -and ($UserSID -eq $denied)) {
                return $false
            }
        }
    }

    # If allowed list is empty, all users are allowed (except those denied)
    if (-not $config.AllowedUsers -or $config.AllowedUsers.Count -eq 0) {
        return $true
    }

    # Check allowed list
    foreach ($allowed in $config.AllowedUsers) {
        if ($Username -like $allowed -or $Username -eq $allowed) {
            return $true
        }
        if ($UserSID -and ($UserSID -eq $allowed)) {
            return $true
        }
    }

    return $false
}

function Get-ValidatedDuration {
    <#
    .SYNOPSIS
        Validates and returns a duration value within configured limits.

    .DESCRIPTION
        Takes a requested duration and ensures it falls within the configured
        minimum and maximum values. Returns the default duration if no value is provided.

    .PARAMETER RequestedDuration
        The duration in minutes requested by the user.

    .OUTPUTS
        Integer representing the validated duration in minutes.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [int]$RequestedDuration = 0
    )

    $config = Get-MakeMeAdminConfig

    if ($RequestedDuration -le 0) {
        return $config.DefaultDurationMinutes
    }

    if ($RequestedDuration -lt $config.MinDurationMinutes) {
        Write-Verbose "Requested duration $RequestedDuration is below minimum. Using $($config.MinDurationMinutes)."
        return $config.MinDurationMinutes
    }

    if ($RequestedDuration -gt $config.MaxDurationMinutes) {
        Write-Verbose "Requested duration $RequestedDuration exceeds maximum. Using $($config.MaxDurationMinutes)."
        return $config.MaxDurationMinutes
    }

    return $RequestedDuration
}

# Export module members (when dot-sourced from module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-MakeMeAdminConfig',
        'Set-MakeMeAdminConfig',
        'Test-MakeMeAdminConfig',
        'Get-StateFilePath',
        'Test-UserAllowed',
        'Get-ValidatedDuration'
    )
}
