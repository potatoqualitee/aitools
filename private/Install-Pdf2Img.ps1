function Install-Pdf2Img {
    <#
    .SYNOPSIS
        Installs the pdf2img binary from GitHub releases.

    .DESCRIPTION
        Downloads and installs the pdf2img binary for the current platform and architecture.
        Supports Windows (amd64), Linux (amd64), macOS Intel (amd64), and macOS ARM (arm64).

        On Windows, installs to $env:LOCALAPPDATA\Programs\pdf2img
        On Linux/macOS, installs to ~/.local/bin

    .OUTPUTS
        PSCustomObject with Path property on success, $null on failure.

    .EXAMPLE
        Install-Pdf2Img
        Downloads and installs pdf2img, returns the installation path.
    #>
    [CmdletBinding()]
    param()

    $toolName = 'pdf2img'
    $gitHubRepo = 'potatoqualitee/pdf2img'

    # Asset patterns for each OS/architecture combination
    $assetPatterns = @{
        'Windows-amd64' = 'pdf2img-windows-amd64.exe'
        'Linux-amd64'   = 'pdf2img-linux-amd64'
        'MacOS-amd64'   = 'pdf2img-darwin-amd64'
        'MacOS-arm64'   = 'pdf2img-darwin-arm64'
    }

    $executableNames = @{
        Windows = 'pdf2img.exe'
        Linux   = 'pdf2img'
        MacOS   = 'pdf2img'
    }

    Write-PSFMessage -Level Verbose -Message "Installing $toolName..."

    # Get OS and architecture
    $os = Get-OperatingSystem
    $arch = Get-ProcessorArchitecture

    Write-PSFMessage -Level Verbose -Message "Detected: $os on $arch"

    # Build the asset key
    $assetKey = "$os-$arch"
    $assetName = $assetPatterns[$assetKey]

    if (-not $assetName) {
        Write-PSFMessage -Level Warning -Message "No $toolName binary available for $os on $arch architecture."
        Write-PSFMessage -Level Warning -Message "Available platforms: $($assetPatterns.Keys -join ', ')"
        return $null
    }

    Write-PSFMessage -Level Verbose -Message "Looking for asset: $assetName"

    # Get the latest release download URL from GitHub API
    $apiUrl = "https://api.github.com/repos/$gitHubRepo/releases/latest"
    Write-PSFMessage -Level Verbose -Message "Fetching release info from: $apiUrl"

    try {
        $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PowerShell-AITools' } -ErrorAction Stop
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to fetch release information from GitHub: $_"
        return $null
    }

    # Find the matching asset
    $asset = $releaseInfo.assets | Where-Object { $_.name -eq $assetName }
    if (-not $asset) {
        $availableAssets = ($releaseInfo.assets | ForEach-Object { $_.name }) -join ', '
        Write-PSFMessage -Level Warning -Message "Asset '$assetName' not found in release. Available: $availableAssets"
        return $null
    }

    $downloadUrl = $asset.browser_download_url
    $releaseVersion = $releaseInfo.tag_name
    Write-PSFMessage -Level Verbose -Message "Download URL: $downloadUrl"
    Write-PSFMessage -Level Verbose -Message "Release version: $releaseVersion"

    # Determine installation directory
    if ($os -eq 'Windows') {
        $installDir = Join-Path $env:LOCALAPPDATA 'Programs\pdf2img'
    } else {
        $installDir = Join-Path $env:HOME '.local/bin'
    }

    Write-PSFMessage -Level Verbose -Message "Installation directory: $installDir"

    # Create directory if it doesn't exist
    if (-not (Test-Path $installDir)) {
        Write-PSFMessage -Level Verbose -Message "Creating installation directory: $installDir"
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    # Download the binary
    $executableName = $executableNames[$os]
    $destinationPath = Join-Path $installDir $executableName

    Write-PSFMessage -Level Host -Message "Downloading $toolName $releaseVersion..."

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $destinationPath -ErrorAction Stop
        $ProgressPreference = 'Continue'
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to download binary: $_"
        return $null
    }

    Write-PSFMessage -Level Verbose -Message "Binary downloaded to: $destinationPath"

    # Set executable permissions on Unix
    if ($os -ne 'Windows') {
        Write-PSFMessage -Level Verbose -Message "Setting executable permissions"
        try {
            & chmod +x $destinationPath 2>&1 | Out-Null
        } catch {
            Write-PSFMessage -Level Warning -Message "Failed to set executable permissions: $_"
        }
    }

    # Add to PATH if not already there
    if ($os -eq 'Windows') {
        # Add to current session PATH
        if (-not ($env:Path -like "*$installDir*")) {
            $env:Path = "$installDir;$env:Path"
            Write-PSFMessage -Level Verbose -Message "Added $installDir to current session PATH"
        }

        # Add to user PATH permanently
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        if (-not ($userPath -like "*$installDir*")) {
            $newUserPath = "$installDir;$userPath"
            [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
            Write-PSFMessage -Level Verbose -Message "Added $installDir to user PATH permanently"
        }
    } else {
        # On Unix, add to current session PATH
        if (-not ($env:PATH -like "*$installDir*")) {
            $env:PATH = "${installDir}:${env:PATH}"
            Write-PSFMessage -Level Verbose -Message "Added $installDir to current session PATH"
        }

        # Add to shell configuration files if not present
        $shellConfigFiles = @()
        $userShell = $env:SHELL
        if ($userShell -match 'zsh') {
            $shellConfigFiles += "${env:HOME}/.zshrc"
        } elseif ($userShell -match 'bash') {
            $shellConfigFiles += "${env:HOME}/.bashrc"
        } else {
            if (Test-Path "${env:HOME}/.zshrc") { $shellConfigFiles += "${env:HOME}/.zshrc" }
            if (Test-Path "${env:HOME}/.bashrc") { $shellConfigFiles += "${env:HOME}/.bashrc" }
        }

        # Add PowerShell profile
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
            if ($configFile -eq $PROFILE) {
                $pathLineToAdd = $pwshPathLine
            } else {
                $pathLineToAdd = $pathExportLine
            }

            $configContent = $null
            if (Test-Path $configFile) {
                $configContent = Get-Content -Path $configFile -Raw -ErrorAction SilentlyContinue
            }

            if (-not ($configContent -match '\.local/bin.*PATH')) {
                Write-PSFMessage -Level Verbose -Message "Adding ~/.local/bin to PATH in $configFile"
                try {
                    Add-Content -Path $configFile -Value "`n# Added by AITools module for pdf2img`n$pathLineToAdd" -Force -ErrorAction Stop
                } catch {
                    Write-PSFMessage -Level Warning -Message "Could not update $configFile"
                }
            }
        }
    }

    # Verify installation
    if (Test-Command -Command $toolName) {
        $version = & $toolName --version 2>&1 | Select-Object -First 1
        Write-PSFMessage -Level Host -Message "$toolName installed successfully ($version)"

        return [PSCustomObject]@{
            Path    = $destinationPath
            Version = $releaseVersion
        }
    } else {
        Write-PSFMessage -Level Warning -Message "$toolName downloaded but command not found. You may need to restart your shell."

        return [PSCustomObject]@{
            Path    = $destinationPath
            Version = $releaseVersion
        }
    }
}
