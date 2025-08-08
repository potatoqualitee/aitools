function Test-AiderAPIKey {
    <#
    .SYNOPSIS
        Checks if Aider has necessary API keys configured.

    .DESCRIPTION
        Checks for ANTHROPIC_API_KEY or OPENAI_API_KEY environment variables required by Aider.

    .OUTPUTS
        Boolean - True if API key found, False otherwise
    #>
    [CmdletBinding()]
    param()

    $anthropicKey = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY')
    $openaiKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY')

    if ($anthropicKey -or $openaiKey) {
        Write-PSFMessage -Level Verbose -Message "Aider API key found"
        return $true
    } else {
        Write-PSFMessage -Level Verbose -Message "No Aider API key found (ANTHROPIC_API_KEY or OPENAI_API_KEY)"
        return $false
    }
}
