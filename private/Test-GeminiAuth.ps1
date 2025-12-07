function Test-GeminiAuth {
    <#
    .SYNOPSIS
        Checks if Gemini CLI has authentication configured.

    .DESCRIPTION
        Checks for GEMINI_API_KEY, GOOGLE_GENAI_USE_VERTEXAI, GOOGLE_GENAI_USE_GCA
        environment variables or ~/.gemini/settings.json file.

    .OUTPUTS
        Boolean - True if auth found, False otherwise
    #>
    [CmdletBinding()]
    param()

    $geminiKey = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY')
    $vertexAI = [Environment]::GetEnvironmentVariable('GOOGLE_GENAI_USE_VERTEXAI')
    $gca = [Environment]::GetEnvironmentVariable('GOOGLE_GENAI_USE_GCA')
    $settingsPath = Join-Path $HOME '.gemini' 'settings.json'

    if ($geminiKey -or $vertexAI -or $gca) {
        Write-PSFMessage -Level Verbose -Message "Gemini auth found via environment variable"
        return $true
    }

    if (Test-Path $settingsPath) {
        Write-PSFMessage -Level Verbose -Message "Gemini settings file found at $settingsPath"
        return $true
    }

    Write-PSFMessage -Level Verbose -Message "No Gemini auth found (GEMINI_API_KEY, GOOGLE_GENAI_USE_VERTEXAI, GOOGLE_GENAI_USE_GCA, or ~/.gemini/settings.json)"
    return $false
}
