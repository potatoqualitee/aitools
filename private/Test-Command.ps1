function Test-Command {
    param(
        [string]$Command,
        [switch]$IsModule
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        Write-PSFMessage -Level Verbose -Message "Command parameter is null or empty"
        return $false
    }

    Write-PSFMessage -Level Verbose -Message "Testing if command exists: $Command"

    # Auto-detect if this is a PowerShell module by checking ToolDefinitions
    # (Special handling for wrapper modules like PSOpenAI)
    if (-not $IsModule) {
        $matchingTool = $script:ToolDefinitions.GetEnumerator() | Where-Object {
            $_.Value.Command -eq $Command -and $_.Value['IsWrapper']
        } | Select-Object -First 1

        if ($matchingTool) {
            Write-PSFMessage -Level Verbose -Message "Detected that '$Command' is a PowerShell module wrapper"
            $IsModule = $true
        }
    }

    # Special handling for PowerShell modules (like PSOpenAI)
    if ($IsModule) {
        Write-PSFMessage -Level Verbose -Message "Testing PowerShell module: $Command"
        $module = Get-Module -ListAvailable -Name $Command -ErrorAction SilentlyContinue
        if ($module) {
            Write-PSFMessage -Level Verbose -Message "Module '$Command' is installed"
            return $true
        } else {
            Write-PSFMessage -Level Verbose -Message "Module '$Command' not found"
            return $false
        }
    }

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Write-PSFMessage -Level Verbose -Message "Command '$Command' not found"
        return $false
    }

    # For script/batch files, verify they can actually execute
    # by checking their dependencies (like node for npm-installed tools)
    # Uses System.Diagnostics.Process with redirected stdin to prevent interactive prompts
    # from shim commands (e.g. gh copilot alias) that detect missing tools and prompt to install
    if ($cmd.CommandType -in 'Application', 'ExternalScript') {
        $process = $null
        try {
            $exePath = $cmd.Source
            if ([string]::IsNullOrWhiteSpace($exePath)) {
                Write-PSFMessage -Level Verbose -Message "Command '$Command' has no Source path, cannot verify"
                return $false
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.RedirectStandardInput = $true

            # .cmd/.bat files on Windows must run via cmd.exe with UseShellExecute=$false
            # .ps1 files must run via powershell.exe
            $extension = [System.IO.Path]::GetExtension($exePath).ToLowerInvariant()
            if ($extension -in '.cmd', '.bat') {
                $psi.FileName = 'cmd.exe'
                $psi.Arguments = "/c `"$exePath`" --version"
            } elseif ($extension -eq '.ps1') {
                # npm global installs create .ps1 shims that can't be executed directly
                # Prefer the .cmd version if available (same directory, same base name)
                $cmdPath = [System.IO.Path]::ChangeExtension($exePath, '.cmd')
                if (Test-Path $cmdPath) {
                    $psi.FileName = 'cmd.exe'
                    $psi.Arguments = "/c `"$cmdPath`" --version"
                    Write-PSFMessage -Level Verbose -Message "Using .cmd shim instead of .ps1: $cmdPath"
                } else {
                    $psi.FileName = 'powershell.exe'
                    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$exePath`" --version"
                }
            } else {
                $psi.FileName = $exePath
                $psi.Arguments = '--version'
            }

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null

            # Close stdin immediately to prevent interactive prompts
            $process.StandardInput.Close()

            # Read output before WaitForExit to avoid deadlock
            $versionOutput = $process.StandardOutput.ReadToEnd()
            $null = $process.StandardError.ReadToEnd()

            if (-not $process.WaitForExit(10000)) {
                Write-PSFMessage -Level Verbose -Message "Command '$Command' timed out after 10 seconds"
                try { $process.Kill() } catch { }
                return $false
            }

            if ($process.ExitCode -ne 0) {
                Write-PSFMessage -Level Verbose -Message "Command '$Command' exited with code $($process.ExitCode)"
                return $false
            }

            $result = ($versionOutput -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)

            if ([string]::IsNullOrWhiteSpace($result)) {
                Write-PSFMessage -Level Verbose -Message "Command '$Command' produced no output"
                return $false
            }

            Write-PSFMessage -Level Verbose -Message "Command '$Command' version check: $($result.Substring(0, [Math]::Min(100, $result.Length)))"

            # Check for common error patterns
            if ($result -match 'not found|command not found|cannot find|no such file') {
                Write-PSFMessage -Level Verbose -Message "Command '$Command' exists but has missing dependencies"
                return $false
            }

            Write-PSFMessage -Level Verbose -Message "Command '$Command' exists and is functional"
            return $true
        } catch {
            Write-PSFMessage -Level Verbose -Message "Command '$Command' exists but failed to execute: $_"
            return $false
        } finally {
            if ($null -ne $process) {
                try { $process.Dispose() } catch { }
            }
        }
    }

    Write-PSFMessage -Level Verbose -Message "Command '$Command' exists: $true"
    return $true
}
