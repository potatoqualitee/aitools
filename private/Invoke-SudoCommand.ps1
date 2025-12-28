function Invoke-SudoCommand {
    <#
    .SYNOPSIS
        Executes a command with sudo if required on Linux.

    .DESCRIPTION
        Wraps command execution to handle sudo requirements on Linux.
        On macOS and Windows, runs commands directly without modification.

        For Linux with LocalMachine scope:
        - Validates sudo access is available before execution
        - Prepends sudo to commands if not running as root
        - Provides clear error messages if sudo access fails

    .PARAMETER Command
        The command to execute.

    .PARAMETER Scope
        The installation scope. Affects whether sudo is needed.

    .PARAMETER Description
        A description of what the command does, for error messages.

    .OUTPUTS
        [PSCustomObject] With properties:
        - Success: [bool] Whether the command succeeded
        - ExitCode: [int] The exit code
        - Output: [string] Combined stdout/stderr
        - Command: [string] The actual command that was run

    .EXAMPLE
        Invoke-SudoCommand -Command 'apt-get update' -Scope LocalMachine -Description 'updating package lists'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter()]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope = 'CurrentUser',

        [Parameter()]
        [string]$Description = 'executing command'
    )

    $os = Get-OperatingSystem
    $needsSudo = Test-SudoRequired -Scope $Scope
    $actualCommand = $Command

    # On Linux with LocalMachine scope, we need to handle sudo
    if ($needsSudo) {
        Write-PSFMessage -Level Verbose -Message "Sudo required for: $Description"

        # First, validate that sudo access is available
        # Use sudo -n (non-interactive) to check if we have passwordless sudo
        # or if sudo credentials are cached
        $sudoCheck = & bash -c 'sudo -n true 2>/dev/null; echo $?' 2>$null
        $hasSudoAccess = ($sudoCheck -eq '0')

        if (-not $hasSudoAccess) {
            # Try to prompt for sudo password by running sudo -v
            # This will cache credentials for subsequent commands
            Write-PSFMessage -Level Host -Message "Elevated privileges required for $Description. You may be prompted for your password."

            # Run sudo -v to prompt for password and cache credentials
            # This needs to be interactive, so we use Start-Process with UseShellExecute
            $validateResult = & bash -c 'sudo -v 2>&1; echo "EXIT:$?"'
            $exitLine = $validateResult | Select-Object -Last 1
            $sudoValidated = $exitLine -eq 'EXIT:0'

            if (-not $sudoValidated) {
                return [PSCustomObject]@{
                    Success  = $false
                    ExitCode = 1
                    Output   = "Failed to obtain sudo privileges. Please ensure you have sudo access and try again."
                    Command  = $Command
                }
            }
        }

        # Prepend sudo to the command if it doesn't already have it
        if ($Command -notmatch '^\s*sudo\s') {
            $actualCommand = "sudo $Command"
        }
    }

    Write-PSFMessage -Level Verbose -Message "Executing: $actualCommand"

    try {
        if ($os -eq 'Windows') {
            # On Windows, use cmd.exe
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'cmd.exe'
            $psi.Arguments = "/c `"$actualCommand`""
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
        } else {
            # On Linux/macOS, use bash
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = '/bin/bash'
            $psi.Arguments = "-c `"$actualCommand`""
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $output = @($stdout, $stderr) | Where-Object { $_ } | Join-String -Separator "`n"

        return [PSCustomObject]@{
            Success  = ($process.ExitCode -eq 0)
            ExitCode = $process.ExitCode
            Output   = $output
            Command  = $actualCommand
        }
    } catch {
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = -1
            Output   = $_.Exception.Message
            Command  = $actualCommand
        }
    }
}
