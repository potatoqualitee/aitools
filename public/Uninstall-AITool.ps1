function Uninstall-AITool {
    <#
    .SYNOPSIS
        Uninstalls the specified AI CLI tool.

    .DESCRIPTION
        Uninstalls AI CLI tools (Claude Code, Aider, Gemini CLI, GitHub Copilot CLI, or OpenAI Codex CLI)
        with cross-platform support for Windows, Linux, and MacOS.

    .PARAMETER Name
        The name of the AI tool to uninstall. Valid values: Claude, Aider, Gemini, Copilot, Codex

    .PARAMETER Force
        Force uninstallation without confirmation prompts.

    .EXAMPLE
        Uninstall-AITool -Name Claude
        Uninstalls Claude Code after confirmation.

    .EXAMPLE
        Uninstall-AITool -Name Aider -Force
        Uninstalls Aider without confirmation.

    .OUTPUTS
        AITools.UninstallResult
        An object containing Tool name, Result (Success/Failed), and Uninstaller command used.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [Alias('Tool')]
        [string]$Name,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting uninstallation of $Name"

        # Resolve tool alias to canonical name
        $resolvedName = Resolve-ToolAlias -ToolName $Name
        Write-PSFMessage -Level Verbose -Message "Resolved tool name: $resolvedName"
    }

    process {
        Write-Progress -Activity "Uninstalling $resolvedName" -Status "Preparing" -PercentComplete 5
        Write-PSFMessage -Level Verbose -Message "Retrieving tool definition for $resolvedName"
        $tool = $script:ToolDefinitions[$resolvedName]
        $os = Get-OperatingSystem

        if (-not $tool) {
            Write-Progress -Activity "Uninstalling $resolvedName" -Completed
            Stop-PSFFunction -Message "Unknown tool: $resolvedName" -EnableException $true
            return
        }

        Write-Progress -Activity "Uninstalling $resolvedName" -Status "Checking installation" -PercentComplete 10
        Write-PSFMessage -Level Verbose -Message "Checking if $resolvedName is installed"

        if (-not (Test-Command -Command $tool.Command)) {
            Write-Progress -Activity "Uninstalling $resolvedName" -Completed
            Write-PSFMessage -Level Warning -Message "$resolvedName is not currently installed."

            [PSCustomObject]@{
                PSTypeName  = 'AITools.UninstallResult'
                Tool        = $resolvedName
                Result      = 'Failed'
                Uninstaller = 'N/A'
            }
            return
        }

        Write-Progress -Activity "Uninstalling $resolvedName" -Status "Detecting installation method" -PercentComplete 15

        # Detect installation method by checking where the command is located
        $commandInfo = Get-Command $tool.Command -ErrorAction SilentlyContinue
        $commandPath = $commandInfo.Source
        if (-not $commandPath) {
            $commandPath = $commandInfo.Path
        }

        Write-PSFMessage -Level Verbose -Message "Command location: $commandPath"

        # Determine the appropriate uninstall command based on installation location
        $uninstallCmd = $tool.UninstallCommands[$os]

        # On Windows, detect if tool was installed via npm vs winget
        if ($os -eq 'Windows' -and $commandPath -match '\\npm\\') {
            Write-PSFMessage -Level Verbose -Message "Detected npm installation (path contains npm directory)"
            # Override with npm uninstall command if available
            $npmUninstallCmd = $tool.UninstallCommands['Linux']  # Linux/MacOS use npm
            if ($npmUninstallCmd -and $npmUninstallCmd -match '^npm') {
                Write-PSFMessage -Level Verbose -Message "Using npm uninstall command instead of default Windows command"
                $uninstallCmd = $npmUninstallCmd
            }
        }

        Write-PSFMessage -Level Verbose -Message "Getting uninstall command for $os"

        if (-not $uninstallCmd) {
            Write-Progress -Activity "Uninstalling $Name" -Completed
            Stop-PSFFunction -Message "No uninstall command defined for $Name on $os" -EnableException $true
            return
        }

        # For Claude on Windows with winget, check if winget is available and fallback to native uninstaller if not
        if ($Name -eq 'Claude' -and $os -eq 'Windows' -and $uninstallCmd -match '^winget') {
            Write-Progress -Activity "Uninstalling $Name" -Status "Checking for winget availability" -PercentComplete 20
            Write-PSFMessage -Level Verbose -Message "Checking if winget is available..."
            if (-not (Test-Command -Command 'winget')) {
                Write-PSFMessage -Level Warning -Message "winget is not available. Falling back to native uninstaller..."
                $uninstallCmd = 'claude uninstall'
                Write-PSFMessage -Level Verbose -Message "Using fallback command: $uninstallCmd"
            } else {
                Write-PSFMessage -Level Verbose -Message "winget is available, proceeding with winget uninstallation"
            }
        }

        # Confirm unless Force is specified
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($Name, "Uninstall AI tool")) {
            Write-Progress -Activity "Uninstalling $Name" -Completed
            Write-PSFMessage -Level Verbose -Message "Uninstallation cancelled by user"
            return
        }

        Write-Progress -Activity "Uninstalling $Name" -Status "Uninstalling" -PercentComplete 30
        Write-PSFMessage -Level Verbose -Message "Uninstalling $Name on $os..."
        Write-PSFMessage -Level Verbose -Message "Command: $uninstallCmd"
        Write-PSFMessage -Level Verbose -Message "Executing uninstall command"

        # Check if this is a PowerShell cmdlet (for wrapper modules like PSOpenAI)
        $isPowerShellCmdlet = $tool.IsWrapper -or $uninstallCmd -match '^(Install-Module|Uninstall-Module|Update-Module|Import-Module)'

        try {
            # Handle PowerShell cmdlets directly
            if ($isPowerShellCmdlet) {
                Write-PSFMessage -Level Verbose -Message "Executing PowerShell cmdlet directly"

                # Parse command and arguments
                $cmdParts = $uninstallCmd -split '\s+', 2
                $cmdletName = $cmdParts[0]

                # Build parameter hashtable from remaining arguments
                $params = @{}
                if ($cmdParts.Count -gt 1) {
                    $argString = $cmdParts[1]
                    if ($argString -match '-Name\s+(\S+)') { $params['Name'] = $matches[1] }
                    if ($argString -match '-Force') { $params['Force'] = $true }
                }

                Write-PSFMessage -Level Verbose -Message "Cmdlet: $cmdletName"
                Write-PSFMessage -Level Verbose -Message "Parameters: $($params | Out-String)"

                # For PowerShell modules, remove from current session first
                if ($cmdletName -eq 'Uninstall-Module' -and $params['Name']) {
                    $moduleName = $params['Name']
                    Write-PSFMessage -Level Verbose -Message "Removing module from current session: $moduleName"
                    $psopenaiall = Get-Module -ListAvailable -Name $moduleName
                    $psopenaiall | Remove-Module -Force -ErrorAction SilentlyContinue
                    $psopenaiall | Uninstall-Module -Force -ErrorAction SilentlyContinue
                }

                $output = & $cmdletName @params 2>&1
                $exitCode = 0
                $stdout = $output | Out-String

                if ($stdout) {
                    $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                        Write-PSFMessage -Level Verbose -Message $_.Trim()
                    }
                }
            } else {
                # Use Start-Process for external executables
                # Split the command into executable and arguments
                $cmdParts = $uninstallCmd -split ' ', 2
                $executable = $cmdParts[0]
                $arguments = if ($cmdParts.Count -gt 1) { $cmdParts[1] } else { '' }

            Write-PSFMessage -Level Verbose -Message "Executable: $executable"
            Write-PSFMessage -Level Verbose -Message "Arguments: $arguments"

            # Resolve the full path to the executable to avoid PATH issues with UseShellExecute = $false
            $executablePath = (Get-Command $executable -ErrorAction SilentlyContinue).Source
            if (-not $executablePath) {
                $executablePath = (Get-Command $executable -ErrorAction SilentlyContinue).Path
            }
            if (-not $executablePath) {
                # If we still can't find it, use the executable as-is and hope for the best
                $executablePath = $executable
            }

            Write-PSFMessage -Level Verbose -Message "Resolved path: $executablePath"

            # If the resolved path is a .ps1 or .cmd file, we need to invoke it through the shell
            # On Windows, npm resolves to npm.ps1 or npm.cmd which can't be directly executed
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            if ($executablePath -match '\.(ps1|cmd)$') {
                Write-PSFMessage -Level Verbose -Message "Detected shell script, using cmd.exe wrapper"
                $psi.FileName = "cmd.exe"
                $psi.Arguments = "/c `"$executable $arguments`""
            } else {
                $psi.FileName = $executablePath
                $psi.Arguments = $arguments
            }
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $psi
                $process.Start() | Out-Null

                $stdout = $process.StandardOutput.ReadToEnd()
                $stderr = $process.StandardError.ReadToEnd()
                $process.WaitForExit()

                # Send output to verbose
                if ($stdout) {
                    $stdout -split "`n" | ForEach-Object { Write-PSFMessage -Level Verbose -Message $_ }
                }
                if ($stderr) {
                    $stderr -split "`n" | ForEach-Object { Write-PSFMessage -Level Verbose -Message $_ }
                }

                $exitCode = $process.ExitCode
            }

            Write-PSFMessage -Level Verbose -Message "Uninstall command completed with exit code: $exitCode"

            # Check if the uninstallation command failed
            if ($exitCode -ne 0) {
                Write-Progress -Activity "Uninstalling $Name" -Completed

                # Provide helpful error messages for common scenarios
                $nl = [Environment]::NewLine
                $errorMessage = "Uninstall command failed with exit code ${exitCode}.${nl}${nl}Command: $uninstallCmd"

                # Debug: Show what we captured
                Write-PSFMessage -Level Verbose -Message "Output text length: $($outputText.Length)"
                if ($outputText.Length -gt 0) {
                    Write-PSFMessage -Level Verbose -Message "Output text preview: $($outputText.Substring(0, [Math]::Min(200, $outputText.Length)))"
                }

                # Provide context-specific help based on the error
                if ($outputText -match "not found" -or $outputText -match "No package found") {
                    $errorMessage += "${nl}${nl}The package may have already been uninstalled or was installed using a different method."
                } elseif ($outputText -match "permission denied" -or $outputText -match "PermissionError") {
                    $errorMessage += "${nl}${nl}Permission denied. Try running with appropriate permissions (sudo on Linux/MacOS, or as Administrator on Windows)."
                } elseif ($outputText -match "pipx") {
                    $errorMessage += "${nl}${nl}pipx may not be installed or configured properly. Ensure pipx is available in your PATH."
                }

                Stop-PSFFunction -Message $errorMessage -EnableException $true
                return
            }

            Write-Progress -Activity "Uninstalling $Name" -Status "Verifying removal" -PercentComplete 85
            Write-PSFMessage -Level Verbose -Message "Verifying uninstallation"

            # Give the system a moment to update the PATH
            Start-Sleep -Milliseconds 500

            if (-not (Test-Command -Command $tool.Command)) {
                Write-PSFMessage -Level Verbose -Message "$Name uninstalled successfully!"
                Write-Progress -Activity "Uninstalling $Name" -Status "Complete" -PercentComplete 100
                Write-Progress -Activity "Uninstalling $Name" -Completed

                # Output directly to pipeline
                [PSCustomObject]@{
                    PSTypeName  = 'AITools.UninstallResult'
                    Tool        = $Name
                    Result      = 'Success'
                    Uninstaller = $uninstallCmd
                }
            } else {
                Write-Progress -Activity "Uninstalling $Name" -Completed
                Write-PSFMessage -Level Warning -Message "$Name uninstall command completed but command is still available. You may need to restart your shell or manually remove it."

                [PSCustomObject]@{
                    PSTypeName  = 'AITools.UninstallResult'
                    Tool        = $Name
                    Result      = 'Failed'
                    Uninstaller = $uninstallCmd
                }
            }
        } catch {
            Write-Progress -Activity "Uninstalling $Name" -Completed
            Stop-PSFFunction -Message "Failed to uninstall $Name : $_" -EnableException $true
        }
    }
}
