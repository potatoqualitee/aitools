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
            $_.Value.Command -eq $Command -and $_.Value.IsWrapper
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
