function Install-AITool {
    <#
    .SYNOPSIS
        Installs the specified AI CLI tool.

    .DESCRIPTION
        Installs AI CLI tools (Claude Code, Aider, Gemini CLI, GitHub Copilot CLI, or OpenAI Codex CLI)
        with cross-platform support for Windows, Linux, and MacOS.

    .PARAMETER Name
        The name of the AI tool to install. Valid values: ClaudeCode, Aider, Gemini, GitHubCopilot, Codex

    .PARAMETER SkipInitialization
        Skip the automatic initialization/login command after installation.
        By default, initialization runs automatically after successful installation.

    .EXAMPLE
        Install-AITool -Name ClaudeCode
        Installs Claude Code, runs initialization, and returns installation details.

    .EXAMPLE
        Install-AITool -Name Aider -SkipInitialization
        Installs Aider without running initialization.

    .EXAMPLE
        Install-AITool -Name All
        Installs all available AI tools sequentially.

    .OUTPUTS
        AITools.InstallResult
        An object containing Tool name, Result (Success/Failed), Version, Path, and Installer command used.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [Alias('Tool')]
        [string]$Name,

        [Parameter()]
        [switch]$SkipInitialization,

        [Parameter()]
        [switch]$SuppressAlreadyInstalledWarning
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting installation of $Name"

        # Handle "All" tool selection
        $toolsToInstall = @()
        if ($Name -eq 'All') {
            Write-PSFMessage -Level Verbose -Message "Name is 'All' - will install all available tools"
            $toolsToInstall = $script:ToolDefinitions.Keys | Sort-Object { $script:ToolDefinitions[$_].Priority }
            Write-PSFMessage -Level Verbose -Message "Tools to install: $($toolsToInstall -join ', ')"
        } else {
            $toolsToInstall = @($Name)
        }
    }

    process {
        foreach ($currentToolName in $toolsToInstall) {
            Write-Progress -Activity "Installing $currentToolName" -Status "Retrieving tool definition for $currentToolName" -PercentComplete 5
            Write-PSFMessage -Level Verbose -Message "Retrieving tool definition for $currentToolName"
            $tool = $script:ToolDefinitions[$currentToolName]

            Write-Progress -Activity "Installing $currentToolName" -Status "Getting OS information" -PercentComplete 5
            $os = Get-OperatingSystem

            if (-not $tool) {
                Write-Progress -Activity "Installing $currentToolName" -Completed
                Write-PSFMessage -Level Warning -Message "Unknown tool: $currentToolName, skipping"
                continue
            }

            Write-Progress -Activity "Installing $currentToolName" -Status "Checking if $currentToolName is already installed" -PercentComplete 10
        Write-PSFMessage -Level Verbose -Message "Checking if $currentToolName is already installed"
        if (Test-Command -Command $tool.Command) {
            # If SuppressAlreadyInstalledWarning is set, we're being called from Update-AITool
            # so we should continue with installation/update instead of returning early
            if (-not $SuppressAlreadyInstalledWarning) {
                $version = & $tool.Command --version 2>&1 | Select-Object -First 1
                Write-PSFMessage -Level Output -Message "$currentToolName is already installed (version: $($version.Trim()))"
                Write-PSFMessage -Level Output -Message "Skipping installation. To reinstall, first run: Uninstall-AITool -Name $currentToolName"

                # Get the full path to the command
                $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Source
                if (-not $commandPath) {
                    $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Path
                }

                Write-Progress -Activity "Installing $currentToolName" -Completed

                # Output existing installation details
                [PSCustomObject]@{
                    PSTypeName = 'AITools.InstallResult'
                    Tool       = $currentToolName
                    Result     = 'Success'
                    Version    = ($version -replace '^.*?(\d+\.\d+\.\d+).*$', '$1').Trim()
                    Path       = $commandPath
                    Installer  = 'Already Installed'
                }
                return
            } else {
                Write-PSFMessage -Level Verbose -Message "$currentToolName is already installed, proceeding with update check..."
            }
        }

            Write-Progress -Activity "Installing $currentToolName" -Status "Getting installation command for $os" -PercentComplete 15
        Write-PSFMessage -Level Verbose -Message "Getting installation command for $os"
        $installCmd = $tool.InstallCommands[$os]

        if (-not $installCmd) {
                Write-Progress -Activity "Installing $currentToolName" -Completed
            Stop-PSFFunction -Message "No installation command defined for $currentToolName on $os" -EnableException $true
            return
        }

        # Ensure $installCmd is an array (convert single command to array)
        if ($installCmd -isnot [array]) {
            $installCmd = @($installCmd)
        }

        # Check for Node.js prerequisite if using npm installation
        if ($installCmd[0] -match '^npm install') {
                Write-Progress -Activity "Installing $currentToolName" -Status "Checking prerequisites" -PercentComplete 20
            Write-PSFMessage -Level Verbose -Message "Checking for Node.js prerequisite (npm-based installation)"
            if (-not (Test-Command -Command 'node')) {
                Write-PSFMessage -Level Warning -Message "Node.js is not installed or not in PATH. Installing Node.js..."

                if ($os -eq 'Linux') {
                        Write-Progress -Activity "Installing $currentToolName" -Status "Installing Node.js prerequisite" -PercentComplete 25
                    Write-PSFMessage -Level Verbose -Message "Installing Node.js via NodeSource repository..."
                    $nodeInstallCmd = 'curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs'
                    try {
                        Invoke-Expression $nodeInstallCmd | Out-Null
                        if (-not (Test-Command -Command 'node')) {
                                Write-Progress -Activity "Installing $currentToolName" -Completed
                            Stop-PSFFunction -Message "Node.js installation failed. Please install Node.js manually and try again." -EnableException $true
                            return
                        }
                        Write-PSFMessage -Level Verbose -Message "Node.js installed successfully."
                    } catch {
                            Write-Progress -Activity "Installing $currentToolName" -Completed
                        Stop-PSFFunction -Message "Failed to install Node.js: $_" -EnableException $true
                        return
                    }
                } elseif ($os -eq 'MacOS') {
                        Write-Progress -Activity "Installing $currentToolName" -Completed
                    Stop-PSFFunction -Message "Node.js is required but not installed. Please install Node.js using: brew install node" -EnableException $true
                    return
                } else {
                        Write-Progress -Activity "Installing $currentToolName" -Completed
                    Stop-PSFFunction -Message "Node.js is required but not installed. Please install Node.js from https://nodejs.org/" -EnableException $true
                    return
                }
            } else {
                $nodeVersion = (& node --version 2>&1 | Out-String).Trim()
                if ($nodeVersion) {
                    Write-PSFMessage -Level Verbose -Message "Node.js is available: $nodeVersion"
                }
            }
        }

            if ($PSCmdlet.ShouldProcess($currentToolName, "Install AI tool")) {
                Write-Progress -Activity "Installing $currentToolName" -Status "Installing (this may take a while)" -PercentComplete 30
            # Sometimes it doesn't update the progress bar right away, do it again
                Write-Progress -Activity "Installing $currentToolName" -Status "Installing (this may take a while)" -PercentComplete 33
            Write-PSFMessage -Level Verbose -Message "Installing $currentToolName on $os..."
            Write-PSFMessage -Level Verbose -Message "Command(s): $($installCmd -join ' ; ')"
            Write-PSFMessage -Level Verbose -Message "Executing installation command(s)"

            try {
                # Execute each command in the array
                $commandIndex = 0
                foreach ($cmd in $installCmd) {
                    $commandIndex++
                    Write-PSFMessage -Level Verbose -Message "Executing command $commandIndex of $($installCmd.Count): $cmd"

                    # Use Start-Process to reliably capture both stdout and stderr
                    # Split the command into executable and arguments
                    $cmdParts = $cmd -split ' ', 2
                    $executable = $cmdParts[0]
                    $arguments = if ($cmdParts.Count -gt 1) { $cmdParts[1] } else { '' }

                    Write-PSFMessage -Level Verbose -Message "Executable: $executable"
                    Write-PSFMessage -Level Verbose -Message "Arguments: $arguments"

                    # Resolve the executable path using Get-Command (handles .cmd, .exe, etc. on Windows)
                    $resolvedExecutable = $null
                    try {
                        # Get all available commands with this name
                        $allCommands = @(Get-Command $executable -All -ErrorAction Stop)

                        # Prefer executables in this order: .exe, .cmd, .bat, then others
                        # Exclude .ps1 files as they can't be run directly by ProcessStartInfo
                        $preferredExtensions = @('.exe', '.cmd', '.bat', '')
                        $selectedCommand = $null

                        foreach ($ext in $preferredExtensions) {
                            $selectedCommand = $allCommands | Where-Object {
                                $_.Source -and (
                                    ($ext -eq '' -and -not $_.Source.EndsWith('.ps1')) -or
                                    $_.Source.EndsWith($ext)
                                )
                            } | Select-Object -First 1
                            if ($selectedCommand) { break }
                        }

                        if ($selectedCommand) {
                            $resolvedExecutable = $selectedCommand.Source
                            if (-not $resolvedExecutable) {
                                $resolvedExecutable = $selectedCommand.Path
                            }
                            Write-PSFMessage -Level Verbose -Message "Resolved executable: $resolvedExecutable"
                        } else {
                            # Fallback to original executable name
                            $resolvedExecutable = $executable
                            Write-PSFMessage -Level Verbose -Message "No suitable executable found, using: $resolvedExecutable"
                        }
                    } catch {
                        # If Get-Command fails, use the original executable name
                        $resolvedExecutable = $executable
                        Write-PSFMessage -Level Verbose -Message "Could not resolve executable path, using: $resolvedExecutable"
                    }

                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $resolvedExecutable
                    $psi.Arguments = $arguments
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

                    $exitCode = $process.ExitCode
                    $outputText = "$stdout`n$stderr"

                    # Send output to verbose (filter out empty lines)
                    if ($stdout) {
                        $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                    }
                    if ($stderr) {
                        $stderr -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                    }

                    Write-PSFMessage -Level Verbose -Message "Command $commandIndex completed with exit code: $exitCode"

                    # Check if the installation command failed
                    # Exit code -1978335189 (0x8A15002B) = APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
                    # This occurs when winget finds the package already installed at the latest version
                    $isAlreadyLatestVersion = ($exitCode -eq -1978335189) -and ($outputText -match 'No available upgrade found|No newer package versions')

                    if ($exitCode -ne 0 -and -not $isAlreadyLatestVersion) {
                            Write-Progress -Activity "Installing $currentToolName" -Completed

                        # Set default parameter for cleaner error output
                        $PSDefaultParameterValues['Write-PSFMessage:Level'] = 'Output'

                        Write-PSFMessage -Message "Installation command $commandIndex failed with exit code ${exitCode}."
                        Write-PSFMessage -Message "Command: $cmd"

                        # Include the actual error output
                        if ($outputText.Trim()) {
                            Write-PSFMessage -Message "Error output:"
                            Write-PSFMessage $outputText.Trim()
                        }

                        Stop-PSFFunction -Message "Installation failed. See error details above." -EnableException $true
                        return
                    } elseif ($isAlreadyLatestVersion) {
                        Write-PSFMessage -Level Verbose -Message "Package is already at the latest version (exit code: $exitCode)"
                    }
                }

                    Write-Progress -Activity "Installing $currentToolName" -Status "Refreshing PATH" -PercentComplete 80
                # Refresh PATH to pick up newly installed tools in the current session
                Write-PSFMessage -Level Verbose -Message "Refreshing PATH environment variable"
                if ($os -eq 'Windows') {
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                    Write-PSFMessage -Level Verbose -Message "Windows PATH refreshed from Machine and User scopes"
                } else {
                    # On Unix, npm global installs go to different locations
                    $npmBin = npm config get prefix 2>$null
                    if ($npmBin) {
                        $env:PATH = "$npmBin/bin:$env:PATH"
                        Write-PSFMessage -Level Verbose -Message "Added npm global bin to PATH: $npmBin/bin"
                    }
                }

                    Write-Progress -Activity "Installing $currentToolName" -Status "Verifying installation" -PercentComplete 85
                Write-PSFMessage -Level Verbose -Message "Verifying installation"
                if (Test-Command -Command $tool.Command) {
                    Write-PSFMessage -Level Verbose -Message "$currentToolName installed successfully!"
                    $version = & $tool.Command --version 2>&1 | Select-Object -First 1
                    Write-PSFMessage -Level Verbose -Message "Version: $version"

                    # Get the full path to the command
                    $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Source
                    if (-not $commandPath) {
                        $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Path
                    }

                    # Run initialization by default unless explicitly skipped
                    if (-not $SkipInitialization) {
                            Write-Progress -Activity "Installing $currentToolName" -Status "Running initialization" -PercentComplete 90
                        Write-PSFMessage -Level Verbose -Message "Running automatic initialization (use -SkipInitialization to skip)"
                        Initialize-AITool -Tool $currentToolName
                    } else {
                        Write-PSFMessage -Level Verbose -Message "Skipping initialization (use Initialize-AITool -Tool $currentToolName to initialize later)"
                    }

                        Write-Progress -Activity "Installing $currentToolName" -Status "Complete" -PercentComplete 100
                        Write-Progress -Activity "Installing $currentToolName" -Completed

                    # Output directly to pipeline
                    [PSCustomObject]@{
                        PSTypeName = 'AITools.InstallResult'
                        Tool       = $currentToolName
                        Result     = 'Success'
                        Version    = ($version -replace '^.*?(\d+\.\d+\.\d+).*$', '$1').Trim()
                        Path       = $commandPath
                        Installer  = ($installCmd -join ' && ')
                    }
                } else {
                        Write-Progress -Activity "Installing $currentToolName" -Completed
                    Write-PSFMessage -Level Error -Message "$currentToolName installation completed but command not found. You may need to restart your shell."

                    [PSCustomObject]@{
                        PSTypeName = 'AITools.InstallResult'
                        Tool       = $currentToolName
                        Result     = 'Failed'
                        Version    = 'N/A'
                        Path       = 'N/A'
                        Installer  = ($installCmd -join ' && ')
                    }
                }
            } catch {
                        Write-Progress -Activity "Installing $currentToolName" -Completed
                    Write-PSFMessage -Level Warning -Message "Failed to install $currentToolName : $_"
                }
            }
        } # End of foreach ($currentToolName in $toolsToInstall)
    }
}
