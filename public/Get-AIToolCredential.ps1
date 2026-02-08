function Get-AIToolCredential {
    <#
    .SYNOPSIS
        Retrieves credentials for an AI tool from various sources.

    .DESCRIPTION
        Looks for credentials in the following order:
        1. Specified credential file path
        2. Environment variables
        3. PSF configuration storage
        4. Default credential file locations

        Returns a hashtable with token and any environment variables to set.

    .PARAMETER Tool
        The AI tool to get credentials for (default: Claude).

    .PARAMETER CredentialPath
        Optional path to a credential/config file.

    .EXAMPLE
        Get-AIToolCredential -Tool Claude

    .EXAMPLE
        Get-AIToolCredential -Tool Claude -CredentialPath "/root/.config/claude.json"

    .OUTPUTS
        Hashtable with:
        - Token: The authentication token (if found)
        - EnvironmentVariables: Hashtable of env vars to set
        - Source: Where the credential was found
        - Configured: Boolean indicating if credentials are available
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tool = 'Claude',

        [Parameter()]
        [string]$CredentialPath
    )

    $result = @{
        Token                = $null
        EnvironmentVariables = @{}
        Source               = $null
        Configured           = $false
    }

    # Tool-specific credential handling
    switch ($Tool) {
        'Claude' {
            # 1. Check specified credential path
            if ($CredentialPath -and (Test-Path $CredentialPath)) {
                try {
                    $config = Get-Content $CredentialPath -Raw | ConvertFrom-Json
                    if ($config.token) {
                        $result.Token = $config.token
                        $result.EnvironmentVariables['CLAUDE_CODE_OAUTH_TOKEN'] = $config.token
                        $result.Source = "CredentialPath: $CredentialPath"
                        $result.Configured = $true
                        Write-PSFMessage -Level Verbose -Message "Claude credential found in specified path: $CredentialPath"
                        return $result
                    }
                }
                catch {
                    Write-PSFMessage -Level Warning -Message "Failed to read credential file: $($_.Exception.Message)"
                }
            }

            # 2. Check environment variable
            $envToken = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN')
            if ($envToken) {
                $result.Token = $envToken
                $result.EnvironmentVariables['CLAUDE_CODE_OAUTH_TOKEN'] = $envToken
                $result.Source = "Environment: CLAUDE_CODE_OAUTH_TOKEN"
                $result.Configured = $true
                Write-PSFMessage -Level Verbose -Message "Claude credential found in environment variable"
                return $result
            }

            # 3. Check PSF configuration
            $storedToken = Get-PSFConfigValue -FullName "AITools.Claude.OAuthToken" -Fallback $null
            if ($storedToken) {
                $result.Token = $storedToken
                $result.EnvironmentVariables['CLAUDE_CODE_OAUTH_TOKEN'] = $storedToken
                $result.Source = "PSFConfig: AITools.Claude.OAuthToken"
                $result.Configured = $true
                Write-PSFMessage -Level Verbose -Message "Claude credential found in PSF configuration"
                return $result
            }

            # 4. Check default Claude credential locations
            # Note: Check $HOME first as it's most likely, /root may have access denied issues
            $defaultPaths = @(
                "$HOME/.claude/.credentials.json"
                "$env:USERPROFILE\.claude\.credentials.json"
                "/root/.claude/.credentials.json"
            )
            foreach ($path in $defaultPaths) {
                # Use -ErrorAction SilentlyContinue to handle access denied errors gracefully
                if ($path -and (Test-Path $path -ErrorAction SilentlyContinue)) {
                    try {
                        $creds = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                        if ($creds.claudeAiOauth.accessToken) {
                            $result.Token = $creds.claudeAiOauth.accessToken
                            $result.EnvironmentVariables['CLAUDE_CODE_OAUTH_TOKEN'] = $creds.claudeAiOauth.accessToken
                            $result.Source = "DefaultPath: $path"
                            $result.Configured = $true
                            Write-PSFMessage -Level Verbose -Message "Claude credential found in default path: $path"
                            return $result
                        }
                    }
                    catch {
                        Write-PSFMessage -Level Debug -Message "Failed to read default credential file $path`: $($_.Exception.Message)"
                    }
                }
            }
        }
        'Aider' {
            # Check for various API keys
            $apiKeys = @{
                'ANTHROPIC_API_KEY' = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY')
                'OPENAI_API_KEY'    = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY')
                'GEMINI_API_KEY'    = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY')
            }

            foreach ($key in $apiKeys.GetEnumerator()) {
                if ($key.Value) {
                    $result.Token = $key.Value
                    $result.EnvironmentVariables[$key.Key] = $key.Value
                    $result.Source = "Environment: $($key.Key)"
                    $result.Configured = $true
                    Write-PSFMessage -Level Verbose -Message "Aider credential found: $($key.Key)"
                    return $result
                }
            }
        }
        'Gemini' {
            $geminiToken = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY')
            if ($geminiToken) {
                $result.Token = $geminiToken
                $result.EnvironmentVariables['GEMINI_API_KEY'] = $geminiToken
                $result.Source = "Environment: GEMINI_API_KEY"
                $result.Configured = $true
                Write-PSFMessage -Level Verbose -Message "Gemini credential found in environment"
                return $result
            }

            $storedToken = Get-PSFConfigValue -FullName "AITools.Gemini.ApiKey" -Fallback $null
            if ($storedToken) {
                $result.Token = $storedToken
                $result.EnvironmentVariables['GEMINI_API_KEY'] = $storedToken
                $result.Source = "PSFConfig: AITools.Gemini.ApiKey"
                $result.Configured = $true
                Write-PSFMessage -Level Verbose -Message "Gemini credential found in PSF configuration"
                return $result
            }
        }
        'Codex' {
            $openaiToken = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY')
            if ($openaiToken) {
                $result.Token = $openaiToken
                $result.EnvironmentVariables['OPENAI_API_KEY'] = $openaiToken
                $result.Source = "Environment: OPENAI_API_KEY"
                $result.Configured = $true
                Write-PSFMessage -Level Verbose -Message "Codex credential found in environment"
                return $result
            }

            $storedToken = Get-PSFConfigValue -FullName "AITools.Codex.ApiKey" -Fallback $null
            if ($storedToken) {
                $result.Token = $storedToken
                $result.EnvironmentVariables['OPENAI_API_KEY'] = $storedToken
                $result.Source = "PSFConfig: AITools.Codex.ApiKey"
                $result.Configured = $true
                Write-PSFMessage -Level Verbose -Message "Codex credential found in PSF configuration"
                return $result
            }
        }
        default {
            Write-PSFMessage -Level Verbose -Message "No credential lookup defined for tool: $Tool"
        }
    }

    Write-PSFMessage -Level Verbose -Message "No credentials found for $Tool"
    return $result
}
