function Test-Command {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        Write-PSFMessage -Level Verbose -Message "Command parameter is null or empty"
        return $false
    }

    Write-PSFMessage -Level Verbose -Message "Testing if command exists: $Command"

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Write-PSFMessage -Level Verbose -Message "Command '$Command' not found"
        return $false
    }

    # For script/batch files, verify they can actually execute
    # by checking their dependencies (like node for npm-installed tools)
    if ($cmd.CommandType -in 'Application', 'ExternalScript') {
        # Try to get version or help to verify it works
        # Use timeout to prevent hanging
        try {
            $result = & $Command --version 2>&1 | Select-Object -First 1
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
        }
    }

    Write-PSFMessage -Level Verbose -Message "Command '$Command' exists: $true"
    return $true
}
