#Requires -Version 5.1
<#
.SYNOPSIS
    Launches an application with elevated privileges through the MakeMeAdminCLI service.

.DESCRIPTION
    The Invoke-AsAdmin cmdlet launches an application with elevation by routing the
    request through the SYSTEM service. The service uses ServiceUI.exe to display the
    process on the user's interactive desktop session, bypassing UAC entirely.

    The user must have an active MakeMeAdminCLI elevation session (via Add-TempAdmin)
    before using this cmdlet. If the user is not currently elevated, the cmdlet will
    fail with a message suggesting Add-TempAdmin.

.NOTES
    Author: MakeMeAdminCLI
    Version: 2.0.0
#>

function Invoke-AsAdmin {
    <#
    .SYNOPSIS
        Launches an application with elevated privileges through the MakeMeAdminCLI service.

    .DESCRIPTION
        Routes process launching through the SYSTEM service using ServiceUI.exe.
        The service launches the process directly, and ServiceUI.exe bridges it to
        the user's interactive desktop session. No UAC prompt is displayed.

        Requires an active MakeMeAdminCLI elevation session (run Add-TempAdmin first).

        Program names that are not full paths are resolved from the system PATH
        using Get-Command, so you can type common names like 'powershell',
        'notepad', or 'cmd.exe'.

    .PARAMETER Program
        The executable name or full path of the program to launch with elevation.
        If not a full path, the cmdlet will attempt to resolve it from PATH.

    .PARAMETER ArgumentList
        Optional arguments to pass to the program being launched.

    .PARAMETER WorkingDirectory
        Sets the working directory for the launched process. If not specified,
        the current directory is used.

    .OUTPUTS
        PSCustomObject
            Returns a result object with Success (bool) and Message (string)
            properties indicating whether the process was launched.

    .EXAMPLE
        Invoke-AsAdmin powershell

        Launches an elevated PowerShell window on the user's desktop.
        No UAC prompt is displayed.

    .EXAMPLE
        Invoke-AsAdmin cmd.exe

        Launches an elevated Command Prompt window.

    .EXAMPLE
        Invoke-AsAdmin notepad "C:\Windows\System32\drivers\etc\hosts"

        Launches Notepad with elevation to edit the hosts file, passing the
        file path as an argument.

    .EXAMPLE
        runas msiexec '/i', 'C:\Installers\setup.msi'

        Uses the 'runas' alias to launch an MSI installer with elevation.

    .EXAMPLE
        Invoke-AsAdmin -Program cmd.exe -WorkingDirectory 'C:\Projects'

        Launches an elevated Command Prompt with the working directory set
        to C:\Projects.

    .LINK
        Add-TempAdmin
        Get-TempAdminStatus
        Remove-TempAdmin
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Program,

        [Parameter(Position = 1, ValueFromRemainingArguments)]
        [string[]]$ArgumentList,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory
    )

    begin {
        # Check if service is running
        if (-not (Test-ServiceRunning)) {
            Write-Error "MakeMeAdminCLI service is not running. Run 'Install-MakeMeAdminCLI' as administrator to start the service."
            return
        }
    }

    process {
        # Resolve the program path if not a full path
        $resolvedProgram = $Program

        if (-not [System.IO.Path]::IsPathRooted($Program)) {
            Write-Verbose "Resolving program '$Program' from PATH..."
            $command = Get-Command -Name $Program -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($command) {
                $resolvedProgram = $command.Source
                Write-Verbose "Resolved to: $resolvedProgram"
            }
            else {
                Write-Error "Program '$Program' was not found. Verify that the program is installed and the name is correct, or provide a full path."
                return
            }
        }
        else {
            # Validate that the specified full path exists
            if (-not (Test-Path $resolvedProgram)) {
                Write-Error "The specified program path '$resolvedProgram' does not exist."
                return
            }
            Write-Verbose "Using specified path: $resolvedProgram"
        }

        # Validate working directory if specified
        if ($WorkingDirectory) {
            if (-not (Test-Path $WorkingDirectory -PathType Container)) {
                Write-Error "The specified working directory '$WorkingDirectory' does not exist."
                return
            }
            Write-Verbose "Working directory: $WorkingDirectory"
        }

        # Build the exec request
        $execRequest = @{
            action   = "exec"
            program  = $resolvedProgram
        }

        if ($ArgumentList -and $ArgumentList.Count -gt 0) {
            $execRequest.arguments = $ArgumentList -join ' '
            Write-Verbose "Arguments: $($execRequest.arguments)"
        }

        if ($WorkingDirectory) {
            $execRequest.workingDirectory = $WorkingDirectory
        }

        # Build description for ShouldProcess
        $processDescription = $resolvedProgram
        if ($ArgumentList) {
            $processDescription += " $($ArgumentList -join ' ')"
        }

        if ($PSCmdlet.ShouldProcess($processDescription, "Launch with elevation via MakeMeAdminCLI service")) {
            Write-Verbose "Sending exec request to service..."
            $response = Send-PipeRequest -Request $execRequest

            if ($null -eq $response) {
                $result = [PSCustomObject]@{
                    Success = $false
                    Message = "Failed to communicate with MakeMeAdminCLI service."
                }
                Write-Error $result.Message
                return $result
            }

            $result = [PSCustomObject]@{
                Success = [bool]$response.success
                Message = $response.message
            }

            if ($result.Success) {
                Write-Verbose "Process launched successfully via service."
            }
            else {
                Write-Error $result.Message
            }

            return $result
        }
    }
}

# Export the function
Export-ModuleMember -Function 'Invoke-AsAdmin'
