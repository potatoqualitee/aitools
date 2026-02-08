function Test-ClaudeAuth {
    <#
    .SYNOPSIS
        Checks if Claude Code has authentication configured.

    .DESCRIPTION
        Checks for CLAUDE_CODE_OAUTH_TOKEN environment variable or stored OAuth token in config.
        Returns true if any valid authentication method is found.

    .OUTPUTS
        Boolean - True if auth found, False otherwise
    #>
    [CmdletBinding()]
    param()

    # Check environment variable first
    $envToken = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN')
    if ($envToken) {
        Write-PSFMessage -Level Verbose -Message "Claude auth found via CLAUDE_CODE_OAUTH_TOKEN environment variable"
        return $true
    }

    # Check stored config
    $storedToken = Get-PSFConfigValue -FullName "AITools.Claude.OAuthToken" -Fallback $null
    if ($storedToken) {
        Write-PSFMessage -Level Verbose -Message "Claude auth found via stored OAuth token in config"
        return $true
    }

    Write-PSFMessage -Level Verbose -Message "No Claude auth found (CLAUDE_CODE_OAUTH_TOKEN env var or stored config)"
    return $false
}
