function Install-AITool {
    <#
    .SYNOPSIS
        Installs the specified AI CLI tool.

    .DESCRIPTION
        Installs AI CLI tools (Claude Code, Aider, Gemini CLI, GitHub Copilot CLI, or OpenAI Codex CLI)
        with cross-platform support for Windows, Linux, and MacOS.

    .PARAMETER Name
        The name of the AI tool to install. Valid values: Claude, Aider, Gemini, Copilot, Codex

    .PARAMETER Version
        The specific version to install (e.g., "1.2.3"). If not specified, installs the latest version.
        If other versions are already installed, you will be prompted to uninstall them.

    .PARAMETER SkipInitialization
        Skip the automatic initialization/login command after installation.
        By default, initialization runs automatically after successful installation.

    .PARAMETER Scope
        Installation scope: CurrentUser (default) or LocalMachine (requires sudo/admin privileges).
        CurrentUser installs to user-local directories without requiring elevated permissions.
        LocalMachine installs system-wide and requires sudo on Linux/MacOS or admin privileges on Windows.

    .PARAMETER UninstallOtherVersions
        Automatically uninstall other versions without prompting. Only applies when -Version is specified.

    .EXAMPLE
        Install-AITool -Name Claude
        Installs Claude Code for the current user, runs initialization, and returns installation details.

    .EXAMPLE
        Install-AITool -Name Aider -SkipInitialization
        Installs Aider for the current user without running initialization.

    .EXAMPLE
        Install-AITool -Name Aider -Scope LocalMachine
        Installs Aider system-wide (requires sudo/admin privileges).

    .EXAMPLE
        Install-AITool -Name Claude -Version 2.0.52
        Installs a specific version of Claude Code. Prompts to uninstall other versions if found.

    .EXAMPLE
        Install-AITool -Name Aider -Version 0.45.0 -UninstallOtherVersions
        Installs Aider version 0.45.0 and automatically uninstalls any other versions without prompting.

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
        [string]$Version,

        [Parameter()]
        [switch]$SkipInitialization,

        [Parameter()]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope = 'CurrentUser',

        [Parameter()]
        [switch]$UninstallOtherVersions,

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
            # Resolve tool alias to canonical name
            $resolvedName = Resolve-ToolAlias -ToolName $Name
            Write-PSFMessage -Level Verbose -Message "Resolved tool name: $resolvedName"
            $toolsToInstall = @($resolvedName)
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

        # Check for existing installations and handle multiple versions
        $existingInstallations = @()
        if (Test-Command -Command $tool.Command) {
            # Get all installed versions
            if ($tool.IsWrapper) {
                $modules = Get-Module -ListAvailable -Name $tool.Command | Sort-Object Version -Descending
                foreach ($module in $modules) {
                    $existingInstallations += [PSCustomObject]@{
                        Version = $module.Version.ToString()
                        Path    = $module.Path
                    }
                }
            } else {
                # For CLI tools, we can only detect the currently active version
                $installedVersion = & $tool.Command --version 2>&1 | Select-Object -First 1
                $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Source
                if (-not $commandPath) {
                    $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Path
                }
                $existingInstallations += [PSCustomObject]@{
                    Version = ($installedVersion -replace '^.*?(\d+\.\d+\.\d+).*$', '$1').Trim()
                    Path    = $commandPath
                }
            }
        }

        # If a specific version is requested and other versions exist, handle them
        if ($Version -and $existingInstallations.Count -gt 0) {
            Write-PSFMessage -Level Verbose -Message "Version $Version requested. Checking for existing installations..."

            # Check if the requested version is already installed
            $requestedVersionInstalled = $existingInstallations | Where-Object { $_.Version -eq $Version }
            $otherVersions = $existingInstallations | Where-Object { $_.Version -ne $Version }

            if ($requestedVersionInstalled) {
                Write-PSFMessage -Level Output -Message "$currentToolName version $Version is already installed"

                if ($otherVersions.Count -gt 0) {
                    Write-PSFMessage -Level Warning -Message "Found $($otherVersions.Count) other version(s) of $currentToolName installed:"
                    foreach ($otherVer in $otherVersions) {
                        Write-PSFMessage -Level Warning -Message "  - Version $($otherVer.Version) at $($otherVer.Path)"
                    }

                    # Prompt to uninstall other versions
                    if (-not $UninstallOtherVersions) {
                        $title = "Uninstall Other Versions"
                        $message = "Do you want to uninstall the other version(s) of $currentToolName?"
                        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Uninstall other versions"
                        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Keep other versions"
                        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                        $result = $Host.UI.PromptForChoice($title, $message, $options, 1)

                        if ($result -eq 0) {
                            $shouldUninstall = $true
                        }
                    } else {
                        $shouldUninstall = $true
                    }

                    if ($shouldUninstall) {
                        Write-PSFMessage -Level Output -Message "Uninstalling other versions of $currentToolName..."
                        try {
                            Uninstall-AITool -Name $currentToolName -ErrorAction Stop
                            Write-PSFMessage -Level Output -Message "Successfully uninstalled other versions"
                        } catch {
                            Write-PSFMessage -Level Warning -Message "Failed to uninstall other versions: $_"
                        }
                    }
                }

                Write-Progress -Activity "Installing $currentToolName" -Completed

                # Output existing installation details
                [PSCustomObject]@{
                    PSTypeName = 'AITools.InstallResult'
                    Tool       = $currentToolName
                    Result     = 'Success'
                    Version    = $Version
                    Path       = $requestedVersionInstalled.Path
                    Installer  = 'Already Installed'
                }
                continue
            } elseif ($otherVersions.Count -gt 0) {
                Write-PSFMessage -Level Warning -Message "Found $($otherVersions.Count) different version(s) of $currentToolName installed:"
                foreach ($otherVer in $otherVersions) {
                    Write-PSFMessage -Level Warning -Message "  - Version $($otherVer.Version) at $($otherVer.Path)"
                }

                # Prompt to uninstall other versions before installing the requested version
                if (-not $UninstallOtherVersions) {
                    $title = "Uninstall Existing Versions"
                    $message = "Do you want to uninstall the existing version(s) before installing version $Version?"
                    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Uninstall existing versions"
                    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Keep existing versions (may cause conflicts)"
                    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                    $result = $Host.UI.PromptForChoice($title, $message, $options, 0)

                    if ($result -eq 0) {
                        $shouldUninstall = $true
                    }
                } else {
                    $shouldUninstall = $true
                }

                if ($shouldUninstall) {
                    Write-PSFMessage -Level Output -Message "Uninstalling existing versions of $currentToolName..."
                    try {
                        Uninstall-AITool -Name $currentToolName -ErrorAction Stop
                        Write-PSFMessage -Level Output -Message "Successfully uninstalled existing versions"
                    } catch {
                        Write-PSFMessage -Level Warning -Message "Failed to uninstall existing versions: $_"
                    }
                }
            }
        } elseif ($existingInstallations.Count -gt 0 -and -not $Version) {
            # No specific version requested, handle existing installation normally
            # If SuppressAlreadyInstalledWarning is set, we're being called from Update-AITool
            # so we should continue with installation/update instead of skipping
            if (-not $SuppressAlreadyInstalledWarning) {
                $latestInstalled = $existingInstallations | Select-Object -First 1

                Write-PSFMessage -Level Output -Message "$currentToolName is already installed (version: $($latestInstalled.Version))"
                Write-PSFMessage -Level Verbose -Message "Skipping installation. To reinstall, first run: Uninstall-AITool -Name $currentToolName"

                Write-Progress -Activity "Installing $currentToolName" -Completed

                # Output existing installation details
                [PSCustomObject]@{
                    PSTypeName = 'AITools.InstallResult'
                    Tool       = $currentToolName
                    Result     = 'Success'
                    Version    = $latestInstalled.Version
                    Path       = $latestInstalled.Path
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

        # Modify install commands to include specific version if requested
        if ($Version) {
            Write-PSFMessage -Level Verbose -Message "Modifying installation command for version $Version"
            $modifiedCmd = @()
            foreach ($cmd in $installCmd) {
                # Handle different package managers and version syntax
                if ($cmd -match '^winget install') {
                    # winget: winget install <package> --version <version>
                    $modifiedCmd += "$cmd --version $Version"
                } elseif ($cmd -match '^npm install -g (.+)') {
                    # npm: npm install -g <package>@<version>
                    $packageName = $Matches[1]
                    $modifiedCmd += "npm install -g ${packageName}@${Version}"
                } elseif ($cmd -match '^pipx install (.+)') {
                    # pipx: pipx install <package>==<version>
                    $packageName = $Matches[1]
                    $modifiedCmd += "pipx install ${packageName}==${Version}"
                } elseif ($cmd -match '^Install-Module -Name (\S+)(.*)') {
                    # PowerShell module: Install-Module -Name <module> -RequiredVersion <version>
                    $moduleName = $Matches[1]
                    $otherParams = $Matches[2]
                    $modifiedCmd += "Install-Module -Name $moduleName -RequiredVersion $Version$otherParams"
                } elseif ($cmd -match '^brew install') {
                    # Homebrew: brew install <package>@<version>
                    # Note: Not all packages support versioned installation in Homebrew
                    Write-PSFMessage -Level Warning -Message "Homebrew version-specific installation may not be supported for all packages"
                    $modifiedCmd += "$cmd@$Version"
                } else {
                    # Unknown package manager or custom command - use as-is and warn
                    Write-PSFMessage -Level Warning -Message "Cannot automatically add version to command: $cmd. Using original command."
                    $modifiedCmd += $cmd
                }
            }
            $installCmd = $modifiedCmd
            Write-PSFMessage -Level Verbose -Message "Modified command(s): $($installCmd -join ' ; ')"
        }

        # For Windows with winget, check if winget is available and sources are healthy
        if ($os -eq 'Windows' -and $installCmd[0] -match '^winget') {
            Write-Progress -Activity "Installing $currentToolName" -Status "Checking for winget availability" -PercentComplete 18
            Write-PSFMessage -Level Verbose -Message "Checking if winget is available..."
            $useWingetFallback = $false

            if (-not (Test-Command -Command 'winget')) {
                Write-PSFMessage -Level Warning -Message "winget is not available. Checking for fallback installer..."
                $useWingetFallback = $true
            } else {
                # Verify winget sources are actually functional (common failure on remote/headless sessions)
                Write-PSFMessage -Level Verbose -Message "Verifying winget sources are functional..."
                $wingetExe = (Get-Command winget -ErrorAction Stop).Source
                try {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $wingetExe
                    $psi.Arguments = 'source list'
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true

                    $process = New-Object System.Diagnostics.Process
                    $process.StartInfo = $psi
                    $process.Start() | Out-Null
                    $null = $process.StandardOutput.ReadToEnd()
                    $wingetSourceErr = $process.StandardError.ReadToEnd()
                    $process.WaitForExit()

                    if ($process.ExitCode -ne 0 -or $wingetSourceErr -match '0x8a15000f|Data required by the source is missing') {
                        Write-PSFMessage -Level Warning -Message "winget sources are not functional. Attempting 'winget source reset --force'..."
                        Write-PSFMessage -Level Verbose -Message "winget source list exit code: $($process.ExitCode)"
                        if ($wingetSourceErr) { Write-PSFMessage -Level Verbose -Message "winget source error: $wingetSourceErr" }

                        # Try to fix winget sources with reset
                        $psi2 = New-Object System.Diagnostics.ProcessStartInfo
                        $psi2.FileName = $wingetExe
                        $psi2.Arguments = 'source reset --force'
                        $psi2.RedirectStandardOutput = $true
                        $psi2.RedirectStandardError = $true
                        $psi2.UseShellExecute = $false
                        $psi2.CreateNoWindow = $true

                        $resetProcess = New-Object System.Diagnostics.Process
                        $resetProcess.StartInfo = $psi2
                        $resetProcess.Start() | Out-Null
                        $resetOut = $resetProcess.StandardOutput.ReadToEnd()
                        $resetErr = $resetProcess.StandardError.ReadToEnd()
                        $resetProcess.WaitForExit()

                        if ($resetProcess.ExitCode -eq 0) {
                            Write-PSFMessage -Level Output -Message "winget sources reset successfully. Proceeding with winget installation."
                            if ($resetOut.Trim()) { Write-PSFMessage -Level Verbose -Message "Reset output: $resetOut" }
                        } else {
                            Write-PSFMessage -Level Warning -Message "winget source reset failed (exit code: $($resetProcess.ExitCode)). Checking for fallback installer..."
                            if ($resetErr) { Write-PSFMessage -Level Verbose -Message "Reset error: $resetErr" }
                            $useWingetFallback = $true
                        }
                    } else {
                        Write-PSFMessage -Level Verbose -Message "winget sources are functional, proceeding with winget installation"
                    }
                } catch {
                    Write-PSFMessage -Level Warning -Message "Failed to verify winget sources: $_. Checking for fallback installer..."
                    $useWingetFallback = $true
                }
            }

            if ($useWingetFallback) {
                $wingetFallbackCmd = if ($tool.FallbackInstallCommands) { $tool.FallbackInstallCommands[$os] } else { $null }
                if ($wingetFallbackCmd) {
                    if ($wingetFallbackCmd -isnot [array]) { $wingetFallbackCmd = @($wingetFallbackCmd) }
                    $installCmd = $wingetFallbackCmd
                    Write-PSFMessage -Level Verbose -Message "Using fallback command: $($installCmd[0])"
                    if ($Version) {
                        Write-PSFMessage -Level Warning -Message "Fallback installer may not install specific version $Version. Latest version will be installed."
                    }
                } else {
                    Write-PSFMessage -Level Warning -Message "winget is not functional and no fallback installer is available for $currentToolName. Attempting winget install anyway..."
                }
            }
        }

        # Install Claude dependencies when in Docker container (critical - Claude exits silently without these)
        if ($currentToolName -eq 'Claude' -and $os -eq 'Linux' -and (Test-DockerContainer)) {
            Write-Progress -Activity "Installing $currentToolName" -Status "Installing Docker dependencies" -PercentComplete 19
            Write-PSFMessage -Level Verbose -Message "Docker container detected - checking Claude Code dependencies..."

            # These are critical: Claude exits silently with code 0 if missing
            $dependencies = @(
                @{ Package = 'ripgrep'; Command = 'rg' }
                @{ Package = 'fzf'; Command = 'fzf' }
                @{ Package = 'zsh'; Command = 'zsh' }
            )

            $missing = @()
            foreach ($dep in $dependencies) {
                if (-not (Test-Command -Command $dep.Command)) {
                    $missing += $dep.Package
                    Write-PSFMessage -Level Verbose -Message "Missing dependency: $($dep.Package)"
                }
            }

            if ($missing.Count -gt 0) {
                Write-PSFMessage -Level Output -Message "Installing Claude dependencies for Docker: $($missing -join ', ')"

                $aptCmd = "apt-get update && apt-get install -y --no-install-recommends $($missing -join ' ')"
                Write-PSFMessage -Level Verbose -Message "Running: $aptCmd"

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = '/bin/bash'
                $psi.Arguments = "-c `"$aptCmd`""
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
                    Write-PSFMessage -Level Warning -Message "Failed to install Docker dependencies. Claude may not work correctly."
                    Write-PSFMessage -Level Warning -Message "Try running manually: $aptCmd"
                    if ($stderr) { Write-PSFMessage -Level Verbose -Message $stderr }
                } else {
                    Write-PSFMessage -Level Verbose -Message "Docker dependencies installed successfully"
                }
            } else {
                Write-PSFMessage -Level Verbose -Message "All Claude dependencies already installed"
            }

            # Warn about inotify limit (causes ENOSPC errors)
            if (Test-Path '/proc/sys/fs/inotify/max_user_watches') {
                $watches = Get-Content '/proc/sys/fs/inotify/max_user_watches' -ErrorAction SilentlyContinue
                if ($watches -and [int]$watches -lt 524288) {
                    Write-PSFMessage -Level Warning -Message "Low inotify limit ($watches) may cause Claude errors. Consider: docker run --sysctl fs.inotify.max_user_watches=524288"
                }
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
                        $pipxInstallCmd = 'apt-get update && apt-get install -y pipx && pipx ensurepath'
                    } else {
                        Write-PSFMessage -Level Verbose -Message "Installing pipx for current user (no sudo required)..."
                        $pipxInstallCmd = 'python3 -m pip install --user pipx && python3 -m pipx ensurepath'
                    }

                    try {
                        # Use Invoke-SudoCommand which handles sudo validation and prompting
                        $result = Invoke-SudoCommand -Command $pipxInstallCmd -Scope $Scope -Description 'installing pipx'

                        if (-not $result.Success) {
                                Write-Progress -Activity "Installing $currentToolName" -Completed
                            if ($Scope -eq 'LocalMachine') {
                                Stop-PSFFunction -Message "pipx installation failed. Please install pipx manually: sudo apt-get install pipx`n$($result.Output)" -EnableException $true
                            } else {
                                Stop-PSFFunction -Message "pipx installation failed. Please install pipx manually: python3 -m pip install --user pipx`n$($result.Output)" -EnableException $true
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
                        # Note: The nodesource script itself needs sudo, so we handle this specially
                        # First download the setup script, then run it with sudo, then install nodejs
                        $nodeInstallCmd = 'curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh && sudo -E bash /tmp/nodesource_setup.sh && sudo apt-get install -y nodejs && rm -f /tmp/nodesource_setup.sh'
                    } else {
                        Write-PSFMessage -Level Verbose -Message "Installing Node.js for current user using nvm (no sudo required)..."
                        $nodeInstallCmd = 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && nvm install --lts && nvm use --lts'
                    }

                    try {
                        if ($Scope -eq 'LocalMachine') {
                            # For LocalMachine, validate sudo access first
                            if (Test-SudoRequired -Scope $Scope) {
                                Write-PSFMessage -Level Host -Message "Elevated privileges required for installing Node.js. You may be prompted for your password."
                                $sudoCheck = & bash -c 'sudo -v 2>&1; echo "EXIT:$?"'
                                $exitLine = $sudoCheck | Select-Object -Last 1
                                if ($exitLine -ne 'EXIT:0') {
                                    Write-Progress -Activity "Installing $currentToolName" -Completed
                                    Stop-PSFFunction -Message "Failed to obtain sudo privileges. Please ensure you have sudo access and try again." -EnableException $true
                                    return
                                }
                            }
                        }

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
                                Stop-PSFFunction -Message "Node.js installation failed. Please install Node.js manually: sudo apt-get install nodejs`n$stdout`n$stderr" -EnableException $true
                            } else {
                                Stop-PSFFunction -Message "Node.js installation failed. Please install Node.js manually using nvm or from https://nodejs.org/`n$stdout`n$stderr" -EnableException $true
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

                    # Check if this is a PowerShell cmdlet (for wrapper modules like PSOpenAI)
                    # PowerShell cmdlets must be executed via Invoke-Expression, not Start-Process
                    $isPowerShellCmdlet = $tool.IsWrapper -or $cmd -match '^(Install-Module|Uninstall-Module|Update-Module|Import-Module)'

                    # Check if command contains shell operators (pipes, redirects, semicolons, etc.)
                    # These require shell execution and can't be handled by Start-Process
                    $requiresShell = $cmd -match '[|&><;]|&&|\|\||iex|Invoke-Expression|Invoke-WebRequest|Start-Process' -or $isPowerShellCmdlet

                    # Handle PowerShell cmdlets directly
                    if ($isPowerShellCmdlet) {
                        Write-PSFMessage -Level Verbose -Message "Executing PowerShell cmdlet directly"
                        try {
                            # Parse command and arguments
                            $cmdParts = $cmd -split '\s+', 2
                            $cmdletName = $cmdParts[0]

                            # Build parameter hashtable from remaining arguments
                            $params = @{}
                            if ($cmdParts.Count -gt 1) {
                                # Simple parsing for -Name value -Scope value patterns
                                $argString = $cmdParts[1]
                                if ($argString -match '-Name\s+(\S+)') { $params['Name'] = $matches[1] }
                                if ($argString -match '-Scope\s+(\S+)') { $params['Scope'] = $matches[1] }
                                if ($argString -match '-Force') { $params['Force'] = $true }
                            }

                            Write-PSFMessage -Level Verbose -Message "Cmdlet: $cmdletName"
                            Write-PSFMessage -Level Verbose -Message "Parameters: $($params | Out-String)"

                            $output = & $cmdletName @params 2>&1
                            $exitCode = 0
                            $stdout = $output | Out-String
                            $stderr = ''
                            $outputText = $stdout
                        } catch {
                            $exitCode = 1
                            $stdout = ''
                            $stderr = $_.Exception.Message
                            $outputText = $stderr
                            Write-PSFMessage -Level Verbose -Message "PowerShell cmdlet failed: $stderr"
                        }
                    } elseif ($requiresShell) {
                        Write-PSFMessage -Level Verbose -Message "Command contains shell operators, using shell execution"

                        # Use appropriate shell based on OS
                        if ($os -eq 'Windows') {
                            # On Windows, use PowerShell for commands with iex/Invoke-Expression or PowerShell-specific syntax
                            if ($cmd -match 'iex|Invoke-Expression|;|Invoke-WebRequest|Start-Process') {
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
                            Write-PSFMessage -Level Verbose -Message "npm ENOTEMPTY error detected. Attempting automatic cleanup and retry..."

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

                        # Generic fallback: try FallbackInstallCommands if primary install failed
                        $hasFallback = $tool.FallbackInstallCommands -and $tool.FallbackInstallCommands[$os]
                        if ($exitCode -ne 0 -and $hasFallback) {
                            $fallbackCmds = $tool.FallbackInstallCommands[$os]
                            if ($fallbackCmds -isnot [array]) { $fallbackCmds = @($fallbackCmds) }

                            # Only try fallback if we're not already executing a fallback command
                            if ($cmd -notin $fallbackCmds) {
                                Write-PSFMessage -Level Warning -Message "Installation failed (exit code: $exitCode). Trying fallback installer..."
                                if ($Version) {
                                    Write-PSFMessage -Level Warning -Message "Fallback installer may not install specific version $Version. Latest version will be installed."
                                }

                                $fallbackExitCode = 0
                                foreach ($fbCmd in $fallbackCmds) {
                                    Write-PSFMessage -Level Verbose -Message "Executing fallback command: $fbCmd"
                                    Write-Progress -Activity "Installing $currentToolName" -Status "Retrying with fallback installer" -PercentComplete 40

                                    try {
                                        Invoke-Expression $fbCmd
                                        $fallbackExitCode = $LASTEXITCODE
                                        if (-not $fallbackExitCode) { $fallbackExitCode = 0 }
                                        Write-PSFMessage -Level Verbose -Message "Fallback command completed with exit code: $fallbackExitCode"
                                    } catch {
                                        Write-PSFMessage -Level Verbose -Message "Fallback command threw an exception: $_"
                                        $fallbackExitCode = 1
                                    }

                                    if ($fallbackExitCode -ne 0) {
                                        Write-PSFMessage -Level Warning -Message "Fallback installer also failed (exit code: $fallbackExitCode)"
                                        break
                                    }
                                }

                                $exitCode = $fallbackExitCode
                                # Update the install command record for the result object
                                if ($exitCode -eq 0) {
                                    $installCmd = $fallbackCmds
                                    break  # Exit the primary install command loop since fallback succeeded
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
                    # For winget installations, explicitly check the WinGet Packages directory first
                    # This works around timing issues where the User PATH registry hasn't propagated yet
                    if ($installCmd[0] -match '^winget install') {
                        Write-PSFMessage -Level Verbose -Message "Winget installation detected - checking WinGet Packages directory"

                        # Find the specific package directory that winget just created
                        $wingetPackagesPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
                        Write-PSFMessage -Level Verbose -Message "Checking for winget packages at: $wingetPackagesPath"

                        if (Test-Path $wingetPackagesPath) {
                            Write-PSFMessage -Level Verbose -Message "WinGet Packages directory exists"

                            # Look for the package directory (e.g., Anthropic.ClaudeCode_*)
                            Write-PSFMessage -Level Verbose -Message "Searching for package directories matching: *$currentToolName*"
                            $packageDirs = Get-ChildItem -Path $wingetPackagesPath -Directory -Filter "*$currentToolName*" -ErrorAction SilentlyContinue
                            Write-PSFMessage -Level Verbose -Message "Found $($packageDirs.Count) package directories with initial filter"

                            if (-not $packageDirs) {
                                # Try alternate package name patterns
                                $alternateNames = @{
                                    'Claude' = 'Anthropic.ClaudeCode*'
                                }
                                if ($alternateNames.ContainsKey($currentToolName)) {
                                    $alternateFilter = $alternateNames[$currentToolName]
                                    Write-PSFMessage -Level Verbose -Message "Trying alternate filter: $alternateFilter"
                                    $packageDirs = Get-ChildItem -Path $wingetPackagesPath -Directory -Filter $alternateFilter -ErrorAction SilentlyContinue
                                    Write-PSFMessage -Level Verbose -Message "Found $($packageDirs.Count) package directories with alternate filter"
                                }
                            }

                            foreach ($packageDir in $packageDirs) {
                                $packagePath = $packageDir.FullName
                                Write-PSFMessage -Level Verbose -Message "Found winget package directory: $packagePath"

                                # Check if the command executable exists in this directory
                                $exePath = Join-Path $packagePath "$($tool.Command).exe"
                                Write-PSFMessage -Level Verbose -Message "Checking for executable at: $exePath"
                                if (Test-Path $exePath) {
                                    Write-PSFMessage -Level Verbose -Message "Executable found!"
                                    if (-not ($env:Path -like "*$packagePath*")) {
                                        $env:Path = "$packagePath;$env:Path"
                                        Write-PSFMessage -Level Verbose -Message "Added winget package path to current session PATH: $packagePath"
                                    } else {
                                        Write-PSFMessage -Level Verbose -Message "Package path already in PATH"
                                    }
                                    break
                                } else {
                                    Write-PSFMessage -Level Verbose -Message "Executable not found at expected path"
                                }
                            }
                        } else {
                            Write-PSFMessage -Level Verbose -Message "WinGet Packages directory does not exist at: $wingetPackagesPath"
                        }
                    }

                    # Now refresh from registry (this may not have propagated yet, but try anyway)
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                    Write-PSFMessage -Level Verbose -Message "Windows PATH refreshed from Machine and User scopes"

                    # For Claude on Windows, also check traditional installation paths as fallback
                    if ($currentToolName -eq 'Claude') {
                        $claudePaths = @(
                            "$env:LOCALAPPDATA\Programs\Claude\resources\app\bin",
                            "$env:LOCALAPPDATA\Programs\Claude\resources\bin",
                            "$env:LOCALAPPDATA\Programs\Claude"
                        )
                        foreach ($claudePath in $claudePaths) {
                            if ((Test-Path $claudePath) -and (-not ($env:Path -like "*$claudePath*"))) {
                                $env:Path = "$claudePath;$env:Path"
                                Write-PSFMessage -Level Verbose -Message "Added Claude installation path to PATH: $claudePath"
                                break
                            }
                        }
                    }
                } else {
                    # On Unix, npm global installs go to different locations
                    $npmBin = npm config get prefix 2>$null
                    if ($npmBin) {
                        $env:PATH = "${npmBin}/bin:${env:PATH}"
                        Write-PSFMessage -Level Verbose -Message "Added npm global bin to PATH: $npmBin/bin"
                    }

                    # pipx, Cursor Agent, and Claude Code install to ~/.local/bin
                    if ($currentToolName -eq 'Cursor' -or $currentToolName -eq 'Aider' -or $currentToolName -eq 'Claude') {
                        $localBin = "${env:HOME}/.local/bin"
                        if (-not ($env:PATH -like "*$localBin*")) {
                            $env:PATH = "${localBin}:${env:PATH}"
                            Write-PSFMessage -Level Verbose -Message "Added ~/.local/bin to PATH: $localBin"
                        }

                        # Auto-configure persistent PATH for Claude, Aider, and Cursor
                        if ($currentToolName -eq 'Claude' -or $currentToolName -eq 'Aider' -or $currentToolName -eq 'Cursor') {
                            Write-PSFMessage -Level Verbose -Message "Checking if ~/.local/bin is in persistent shell configuration..."

                            # Detect the shell and configure accordingly
                            $shellConfigFiles = @()

                            # Determine user's default shell and add appropriate config file
                            $userShell = $env:SHELL
                            if ($userShell -match 'zsh') {
                                # Zsh configuration (default on macOS)
                                $shellConfigFiles += "${env:HOME}/.zshrc"
                            } elseif ($userShell -match 'bash') {
                                # Bash configuration (common on Linux)
                                # Prefer .bashrc for interactive shells
                                $shellConfigFiles += "${env:HOME}/.bashrc"
                            } else {
                                # Fallback: add config files that already exist
                                if (Test-Path "${env:HOME}/.zshrc") {
                                    $shellConfigFiles += "${env:HOME}/.zshrc"
                                }
                                if (Test-Path "${env:HOME}/.bashrc") {
                                    $shellConfigFiles += "${env:HOME}/.bashrc"
                                }
                            }

                            # PowerShell profile (for PowerShell on Linux/macOS)
                            if ($PROFILE) {
                                $profileDir = Split-Path -Parent $PROFILE
                                if (-not (Test-Path $profileDir)) {
                                    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                                }
                                if (-not (Test-Path $PROFILE)) {
                                    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
                                }
                                $shellConfigFiles += $PROFILE
                            }

                            $pathExportLine = 'export PATH="$HOME/.local/bin:$PATH"'
                            $pwshPathLine = '$env:PATH = "$env:HOME/.local/bin:$env:PATH"'

                            foreach ($configFile in $shellConfigFiles) {
                                # Determine which PATH line to use based on file type
                                if ($configFile -eq $PROFILE) {
                                    $pathLineToAdd = $pwshPathLine
                                    $searchPattern = '\.local/bin.*PATH'
                                } else {
                                    $pathLineToAdd = $pathExportLine
                                    $searchPattern = '\.local/bin.*PATH'
                                }

                                # Get existing content if file exists
                                $configContent = $null
                                if (Test-Path $configFile) {
                                    $configContent = Get-Content -Path $configFile -Raw -ErrorAction SilentlyContinue
                                }

                                # Check if PATH configuration already exists
                                if (-not ($configContent -match $searchPattern)) {
                                    Write-PSFMessage -Level Verbose -Message "Adding ~/.local/bin to PATH in $configFile"

                                    # Add PATH configuration to the config file (creates file if it doesn't exist)
                                    try {
                                        Add-Content -Path $configFile -Value "`n# Added by AITools module for $currentToolName`n$pathLineToAdd" -Force -ErrorAction Stop
                                        Write-PSFMessage -Level Output -Message "✅ Added ~/.local/bin to PATH in $configFile"
                                    } catch {
                                        Write-PSFMessage -Level Warning -Message "Could not update $configFile (access denied or file is read-only). You may need to manually add: $pathLineToAdd"
                                    }
                                } else {
                                    Write-PSFMessage -Level Verbose -Message "~/.local/bin already in PATH configuration in $configFile"
                                }
                            }

                            if ($shellConfigFiles.Count -eq 0) {
                                Write-PSFMessage -Level Warning -Message "No shell configuration files found. Please add ~/.local/bin to your PATH manually."
                            }
                        }
                    }
                }

                    Write-Progress -Activity "Installing $currentToolName" -Status "Verifying installation" -PercentComplete 85
                Write-PSFMessage -Level Verbose -Message "Verifying installation"
                if (Test-Command -Command $tool.Command) {
                    Write-PSFMessage -Level Verbose -Message "$currentToolName installed successfully!"

                    # Get version differently for PowerShell modules vs CLIs
                    if ($tool.IsWrapper) {
                        $module = Get-Module -ListAvailable -Name $tool.Command | Sort-Object Version -Descending | Select-Object -First 1
                        $version = $module.Version.ToString()
                        $commandPath = $module.Path
                    } else {
                        $version = & $tool.Command --version 2>&1 | Select-Object -First 1
                        # Get the full path to the command
                        $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Source
                        if (-not $commandPath) {
                            $commandPath = (Get-Command $tool.Command -ErrorAction SilentlyContinue).Path
                        }
                    }

                    Write-PSFMessage -Level Verbose -Message "Version: $version"

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
