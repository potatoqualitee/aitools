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

    .PARAMETER Scope
        Installation scope: CurrentUser (default) or LocalMachine (requires sudo/admin privileges).
        CurrentUser installs to user-local directories without requiring elevated permissions.
        LocalMachine installs system-wide and requires sudo on Linux/MacOS or admin privileges on Windows.

    .EXAMPLE
        Install-AITool -Name ClaudeCode
        Installs Claude Code for the current user, runs initialization, and returns installation details.

    .EXAMPLE
        Install-AITool -Name Aider -SkipInitialization
        Installs Aider for the current user without running initialization.

    .EXAMPLE
        Install-AITool -Name Aider -Scope LocalMachine
        Installs Aider system-wide (requires sudo/admin privileges).

    .EXAMPLE
        Install-AITool -Name All
        Installs all available AI tools sequentially for the current user.

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
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope = 'CurrentUser',

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
            # so we should continue with installation/update instead of skipping
            if (-not $SuppressAlreadyInstalledWarning) {
                $version = & $tool.Command --version 2>&1 | Select-Object -First 1
                Write-PSFMessage -Level Output -Message "$currentToolName is already installed (version: $($version.Trim()))"
                Write-PSFMessage -Level Verbose -Message "Skipping installation. To reinstall, first run: Uninstall-AITool -Name $currentToolName"

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
                continue
            } else {
                Write-PSFMessage -Level Verbose -Message "$currentToolName is already installed, proceeding with update check..."
            }
        }

            Write-Progress -Activity "Installing $currentToolName" -Status "Getting installation command for $os" -PercentComplete 15
        Write-PSFMessage -Level Verbose -Message "Getting installation command for $os"
        $installCmd = $tool.InstallCommands[$os]

        if (-not $installCmd) {
                Write-Progress -Activity "Installing $currentToolName" -Completed
            # Special message for Cursor on Windows
            if ($currentToolName -eq 'Cursor' -and $os -eq 'Windows') {
                Stop-PSFFunction -Message "Native Windows installation is not supported for $currentToolName. Please use WSL (Windows Subsystem for Linux) or install on Linux/MacOS." -EnableException $true
            } else {
                Stop-PSFFunction -Message "No installation command defined for $currentToolName on $os" -EnableException $true
            }
            return
        }

        # Ensure $installCmd is an array (convert single command to array)
        if ($installCmd -isnot [array]) {
            $installCmd = @($installCmd)
        }

        # For ClaudeCode on Windows with winget, check if winget is available and fallback to PowerShell installer if not
        if ($currentToolName -eq 'ClaudeCode' -and $os -eq 'Windows' -and $installCmd[0] -match '^winget') {
            Write-Progress -Activity "Installing $currentToolName" -Status "Checking for winget availability" -PercentComplete 18
            Write-PSFMessage -Level Verbose -Message "Checking if winget is available..."
            if (-not (Test-Command -Command 'winget')) {
                Write-PSFMessage -Level Warning -Message "winget is not available. Falling back to PowerShell installer..."
                $installCmd = @('irm https://claude.ai/install.ps1 | iex')
                Write-PSFMessage -Level Verbose -Message "Using fallback command: $($installCmd[0])"
            } else {
                Write-PSFMessage -Level Verbose -Message "winget is available, proceeding with winget installation"
            }
        }

        # Check for pipx prerequisite if using pipx installation
        if ($installCmd[0] -match '^pipx install') {
                Write-Progress -Activity "Installing $currentToolName" -Status "Checking prerequisites" -PercentComplete 20
            Write-PSFMessage -Level Verbose -Message "Checking for pipx prerequisite (pipx-based installation)"
            if (-not (Test-Command -Command 'pipx')) {
                Write-PSFMessage -Level Warning -Message "pipx is not installed or not in PATH. Installing pipx..."

                if ($os -eq 'Linux') {
                        Write-Progress -Activity "Installing $currentToolName" -Status "Installing pipx prerequisite" -PercentComplete 25

                    # Choose installation method based on Scope
                    if ($Scope -eq 'LocalMachine') {
                        Write-PSFMessage -Level Verbose -Message "Installing pipx system-wide (requires sudo)..."
                        $pipxInstallCmd = 'sudo apt-get update && sudo apt-get install -y pipx && pipx ensurepath'
                    } else {
                        Write-PSFMessage -Level Verbose -Message "Installing pipx for current user (no sudo required)..."
                        $pipxInstallCmd = 'python3 -m pip install --user pipx && python3 -m pipx ensurepath'
                    }

                    try {
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = '/bin/bash'
                        $psi.Arguments = "-c `"$pipxInstallCmd`""
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

                        if ($process.ExitCode -ne 0) {
                                Write-Progress -Activity "Installing $currentToolName" -Completed
                            if ($Scope -eq 'LocalMachine') {
                                Stop-PSFFunction -Message "pipx installation failed. Please install pipx manually: sudo apt-get install pipx" -EnableException $true
                            } else {
                                Stop-PSFFunction -Message "pipx installation failed. Please install pipx manually: python3 -m pip install --user pipx" -EnableException $true
                            }
                            return
                        }

                        # Refresh PATH to pick up pipx
                        $pipxBin = "${env:HOME}/.local/bin"
                        if (-not ($env:PATH -like "*$pipxBin*")) {
                            $env:PATH = "${pipxBin}:${env:PATH}"
                        }

                        if (-not (Test-Command -Command 'pipx')) {
                                Write-Progress -Activity "Installing $currentToolName" -Completed
                            Stop-PSFFunction -Message "pipx installation failed. Please install pipx manually and try again." -EnableException $true
                            return
                        }
                        Write-PSFMessage -Level Verbose -Message "pipx installed successfully."
                    } catch {
                            Write-Progress -Activity "Installing $currentToolName" -Completed
                        Stop-PSFFunction -Message "Failed to install pipx: $_" -EnableException $true
                        return
                    }
                } elseif ($os -eq 'MacOS') {
                        Write-Progress -Activity "Installing $currentToolName" -Completed
                    if ($Scope -eq 'LocalMachine') {
                        Stop-PSFFunction -Message "pipx is required but not installed. Please install pipx using: brew install pipx" -EnableException $true
                    } else {
                        Stop-PSFFunction -Message "pipx is required but not installed. Please install pipx using: python3 -m pip install --user pipx && python3 -m pipx ensurepath" -EnableException $true
                    }
                    return
                } else {
                        Write-Progress -Activity "Installing $currentToolName" -Completed
                    Stop-PSFFunction -Message "pipx is required but not installed. Please install pipx using: python -m pip install --user pipx" -EnableException $true
                    return
                }
            } else {
                $pipxVersion = (& pipx --version 2>&1 | Out-String).Trim()
                if ($pipxVersion) {
                    Write-PSFMessage -Level Verbose -Message "pipx is available: $pipxVersion"
                }
            }
        }

        # Check for Node.js prerequisite if using npm installation
        if ($installCmd[0] -match '^npm install') {
                Write-Progress -Activity "Installing $currentToolName" -Status "Checking prerequisites" -PercentComplete 20
            Write-PSFMessage -Level Verbose -Message "Checking for Node.js prerequisite (npm-based installation)"
            if (-not (Test-Command -Command 'node')) {
                Write-PSFMessage -Level Warning -Message "Node.js is not installed or not in PATH. Installing Node.js..."

                if ($os -eq 'Linux') {
                        Write-Progress -Activity "Installing $currentToolName" -Status "Installing Node.js prerequisite" -PercentComplete 25

                    # Choose installation method based on Scope
                    if ($Scope -eq 'LocalMachine') {
                        Write-PSFMessage -Level Verbose -Message "Installing Node.js system-wide (requires sudo)..."
                        $nodeInstallCmd = 'curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs'
                    } else {
                        Write-PSFMessage -Level Verbose -Message "Installing Node.js for current user using nvm (no sudo required)..."
                        $nodeInstallCmd = 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && nvm install --lts && nvm use --lts'
                    }

                    try {
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = '/bin/bash'
                        $psi.Arguments = "-c `"$nodeInstallCmd`""
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

                        if ($process.ExitCode -ne 0) {
                                Write-Progress -Activity "Installing $currentToolName" -Completed
                            if ($Scope -eq 'LocalMachine') {
                                Stop-PSFFunction -Message "Node.js installation failed. Please install Node.js manually: sudo apt-get install nodejs" -EnableException $true
                            } else {
                                Stop-PSFFunction -Message "Node.js installation failed. Please install Node.js manually using nvm or from https://nodejs.org/" -EnableException $true
                            }
                            return
                        }

                        # Refresh PATH to pick up Node.js
                        if ($Scope -eq 'CurrentUser') {
                            # For nvm, we need to source the nvm script and add to PATH
                            $nvmDir = "${env:HOME}/.nvm"
                            if (Test-Path "$nvmDir/nvm.sh") {
                                # Get the node path from nvm
                                $nvmNodePath = & /bin/bash -c "export NVM_DIR=`"$nvmDir`" && [ -s `"`$NVM_DIR/nvm.sh`" ] && \. `"`$NVM_DIR/nvm.sh`" && command -v node" 2>&1
                                if ($nvmNodePath) {
                                    $nvmBinPath = Split-Path -Parent $nvmNodePath
                                    if (-not ($env:PATH -like "*$nvmBinPath*")) {
                                        $env:PATH = "${nvmBinPath}:${env:PATH}"
                                    }
                                }
                            }
                        }

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
                    if ($Scope -eq 'LocalMachine') {
                        Stop-PSFFunction -Message "Node.js is required but not installed. Please install Node.js using: brew install node" -EnableException $true
                    } else {
                        Stop-PSFFunction -Message "Node.js is required but not installed. Please install Node.js using nvm or from https://nodejs.org/" -EnableException $true
                    }
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

                    # Check if command contains shell operators (pipes, redirects, etc.)
                    # These require shell execution and can't be handled by Start-Process
                    $requiresShell = $cmd -match '[|&><]|&&|\|\||iex|Invoke-Expression'

                    if ($requiresShell) {
                        Write-PSFMessage -Level Verbose -Message "Command contains shell operators, using shell execution"

                        # Use appropriate shell based on OS
                        if ($os -eq 'Windows') {
                            # On Windows, use PowerShell for commands with iex/Invoke-Expression
                            if ($cmd -match 'iex|Invoke-Expression') {
                                Write-PSFMessage -Level Verbose -Message "Executing via Invoke-Expression"
                                Invoke-Expression $cmd
                                $exitCode = $LASTEXITCODE
                                if (-not $exitCode) { $exitCode = 0 }
                            } else {
                                # Use cmd.exe for other shell operators
                                Write-PSFMessage -Level Verbose -Message "Executing via cmd.exe"
                                $psi = New-Object System.Diagnostics.ProcessStartInfo
                                $psi.FileName = 'cmd.exe'
                                $psi.Arguments = "/c $cmd"
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

                                if ($stdout) {
                                    $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                                }
                                if ($stderr) {
                                    $stderr -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                                }
                            }
                        } else {
                            # On Unix, use bash or sh
                            Write-PSFMessage -Level Verbose -Message "Executing via shell"
                            $shellCmd = if (Test-Path '/bin/bash') { '/bin/bash' } else { '/bin/sh' }

                            $psi = New-Object System.Diagnostics.ProcessStartInfo
                            $psi.FileName = $shellCmd
                            $psi.Arguments = "-c `"$cmd`""
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

                            if ($stdout) {
                                $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                            }
                            if ($stderr) {
                                $stderr -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                            }
                        }

                        $outputText = "$stdout`n$stderr"
                    } else {
                        # Simple command without shell operators - use Start-Process directly
                        Write-PSFMessage -Level Verbose -Message "Simple command, using Start-Process"

                        # Split the command into executable and arguments
                        $cmdParts = $cmd -split ' ', 2
                        $executable = $cmdParts[0]
                        $arguments = if ($cmdParts.Count -gt 1) { $cmdParts[1] } else { '' }

                        # Handle python/python3 fallback on Linux/MacOS
                        if ($executable -eq 'python' -and $os -ne 'Windows') {
                            Write-PSFMessage -Level Verbose -Message "Checking for python3 alternative on Unix system"
                            if (-not (Test-Command -Command 'python') -and (Test-Command -Command 'python3')) {
                                Write-PSFMessage -Level Verbose -Message "python not found, using python3 instead"
                                $executable = 'python3'
                            }
                        }

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
                    }

                    Write-PSFMessage -Level Verbose -Message "Command $commandIndex completed with exit code: $exitCode"

                    # Check if the installation command failed
                    # Exit code -1978335189 (0x8A15002B) = APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
                    # This occurs when winget finds the package already installed at the latest version
                    $isAlreadyLatestVersion = ($exitCode -eq -1978335189) -and ($outputText -match 'No available upgrade found|No newer package versions')

                    if ($exitCode -ne 0 -and -not $isAlreadyLatestVersion) {
                        # Check for npm ENOTEMPTY error (exit code 217 or stderr contains ENOTEMPTY)
                        $isNpmEnotemptyError = ($exitCode -eq 217 -or $outputText -match 'ENOTEMPTY|directory not empty') -and $cmd -match '^npm install'

                        if ($isNpmEnotemptyError) {
                            Write-PSFMessage -Level Warning -Message "npm ENOTEMPTY error detected. Attempting automatic cleanup and retry..."

                            # Extract package name from npm install command
                            $packageName = $null
                            if ($cmd -match 'npm install -g (.+)') {
                                $packageName = $Matches[1].Trim()
                                Write-PSFMessage -Level Verbose -Message "Extracted package name: $packageName"

                                # Determine npm global lib path
                                $npmPrefix = & npm config get prefix 2>&1 | Out-String
                                $npmPrefix = $npmPrefix.Trim()

                                if ($npmPrefix) {
                                    $packagePath = Join-Path $npmPrefix "lib/node_modules/$packageName"
                                    Write-PSFMessage -Level Verbose -Message "Package path: $packagePath"

                                    # Remove the problematic directory
                                    if (Test-Path $packagePath) {
                                        Write-PSFMessage -Level Verbose -Message "Removing problematic directory: $packagePath"
                                        try {
                                            Remove-Item -Path $packagePath -Recurse -Force -ErrorAction Stop
                                            Write-PSFMessage -Level Verbose -Message "Directory removed successfully"
                                        } catch {
                                            Write-PSFMessage -Level Warning -Message "Failed to remove directory: $_"
                                        }
                                    } else {
                                        Write-PSFMessage -Level Verbose -Message "Package directory not found at expected location"
                                    }

                                    # Retry the installation
                                    Write-PSFMessage -Level Verbose -Message "Retrying installation command: $cmd"
                                    Write-Progress -Activity "Installing $currentToolName" -Status "Retrying after cleanup (this may take a while)" -PercentComplete 40

                                    # Re-execute the same command logic
                                    if ($requiresShell) {
                                        if ($os -eq 'Windows') {
                                            $psi = New-Object System.Diagnostics.ProcessStartInfo
                                            $psi.FileName = 'cmd.exe'
                                            $psi.Arguments = "/c $cmd"
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
                                        } else {
                                            $shellCmd = if (Test-Path '/bin/bash') { '/bin/bash' } else { '/bin/sh' }
                                            $psi = New-Object System.Diagnostics.ProcessStartInfo
                                            $psi.FileName = $shellCmd
                                            $psi.Arguments = "-c `"$cmd`""
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
                                        }
                                        $outputText = "$stdout`n$stderr"
                                    } else {
                                        # Re-execute using Start-Process for simple commands
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
                                    }

                                    if ($stdout) {
                                        $stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                                    }
                                    if ($stderr) {
                                        $stderr -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $trimmed = $_.Trim(); if ($trimmed) { Write-PSFMessage -Level Verbose -Message $trimmed } }
                                    }

                                    Write-PSFMessage -Level Verbose -Message "Retry completed with exit code: $exitCode"

                                    # If retry still failed, fall through to normal error handling
                                    if ($exitCode -ne 0) {
                                        Write-PSFMessage -Level Warning -Message "Retry failed. Falling back to normal error handling."
                                    } else {
                                        Write-PSFMessage -Level Verbose -Message "Retry successful!"
                                        # Continue to next command
                                        continue
                                    }
                                }
                            }
                        }

                        # Normal error handling if not npm ENOTEMPTY or retry failed
                        if ($exitCode -ne 0) {
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
                        }
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
                        $env:PATH = "${npmBin}/bin:${env:PATH}"
                        Write-PSFMessage -Level Verbose -Message "Added npm global bin to PATH: $npmBin/bin"
                    }

                    # pipx and Cursor Agent install to ~/.local/bin
                    if ($currentToolName -eq 'Cursor' -or $currentToolName -eq 'Aider') {
                        $localBin = "${env:HOME}/.local/bin"
                        if (-not ($env:PATH -like "*$localBin*")) {
                            $env:PATH = "${localBin}:${env:PATH}"
                            Write-PSFMessage -Level Verbose -Message "Added ~/.local/bin to PATH: $localBin"
                        }
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

                    # Provide tool-specific guidance for post-install issues
                    $additionalMessage = ""
                    if ($currentToolName -eq 'Cursor' -and $os -ne 'Windows') {
                        $additionalMessage = " Add ~/.local/bin to your PATH by running: echo 'export PATH=`$HOME/.local/bin:`$PATH' >> ~/.bashrc && source ~/.bashrc"
                    }

                    Write-PSFMessage -Level Warning -Message "$currentToolName installation completed but command not found. You may need to restart your shell.$additionalMessage"

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
