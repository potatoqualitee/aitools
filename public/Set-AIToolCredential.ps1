function Set-AIToolCredential {
    <#
    .SYNOPSIS
        Stores credentials for an AI tool.

    .DESCRIPTION
        Saves credentials for AI tools to various locations:
        - PSF configuration (encrypted, persisted)
        - Environment variables (current process)
        - Optional file path (JSON format)

        Credentials stored via PSF configuration persist across PowerShell sessions.

    .PARAMETER Tool
        The AI tool to store credentials for (default: Claude).

    .PARAMETER Token
        The authentication token to store.

    .PARAMETER FilePath
        Optional file path to also save credentials to (JSON format).

    .PARAMETER EnvironmentOnly
        Only set the environment variable, don't persist to PSF configuration.

    .EXAMPLE
        Set-AIToolCredential -Tool Claude -Token "sk-ant-xxxxx"

    .EXAMPLE
        Set-AIToolCredential -Tool Claude -Token $token -FilePath "/config/claude.json"

    .EXAMPLE
        Set-AIToolCredential -Tool Gemini -Token $apiKey -EnvironmentOnly

    .OUTPUTS
        PSCustomObject with:
        - Success: Boolean indicating if save was successful
        - Locations: Array of locations where credential was saved
        - Message: Status message
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$Tool = 'Claude',

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter()]
        [string]$FilePath,

        [Parameter()]
        [switch]$EnvironmentOnly
    )

    # Clean up token - remove whitespace, line breaks
    $Token = $Token -replace '[\r\n\s]', ''

    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw "Token cannot be empty"
    }

    $savedLocations = @()
    $result = [PSCustomObject]@{
        Success   = $false
        Locations = @()
        Message   = ""
    }

    # Tool-specific validation and storage
    switch ($Tool) {
        'Claude' {
            # Validate Claude token format
            if ($Token -notmatch '^sk-ant-') {
                throw "Invalid Claude token format. Tokens should start with 'sk-ant-'"
            }

            $envVarName = 'CLAUDE_CODE_OAUTH_TOKEN'
            $configName = 'AITools.Claude.OAuthToken'
        }
        'Aider' {
            # Aider uses various API keys - detect by format
            if ($Token -match '^sk-ant-') {
                $envVarName = 'ANTHROPIC_API_KEY'
                $configName = 'AITools.Aider.AnthropicApiKey'
            }
            elseif ($Token -match '^sk-') {
                $envVarName = 'OPENAI_API_KEY'
                $configName = 'AITools.Aider.OpenAiApiKey'
            }
            else {
                $envVarName = 'ANTHROPIC_API_KEY'
                $configName = 'AITools.Aider.ApiKey'
            }
        }
        'Gemini' {
            $envVarName = 'GEMINI_API_KEY'
            $configName = 'AITools.Gemini.ApiKey'
        }
        'Codex' {
            if ($Token -notmatch '^sk-') {
                Write-PSFMessage -Level Warning -Message "OpenAI tokens typically start with 'sk-'"
            }
            $envVarName = 'OPENAI_API_KEY'
            $configName = 'AITools.Codex.ApiKey'
        }
        default {
            throw "Credential storage not implemented for tool: $Tool"
        }
    }

    try {
        # 1. Set environment variable (always do this for immediate use)
        if ($PSCmdlet.ShouldProcess($envVarName, "Set environment variable")) {
            [Environment]::SetEnvironmentVariable($envVarName, $Token, 'Process')
            $savedLocations += "Environment: $envVarName"
            Write-PSFMessage -Level Verbose -Message "Set environment variable: $envVarName"
        }

        # 2. Save to PSF configuration (unless EnvironmentOnly)
        if (-not $EnvironmentOnly) {
            if ($PSCmdlet.ShouldProcess($configName, "Save to PSF configuration")) {
                Set-PSFConfig -FullName $configName -Value $Token -PassThru | Register-PSFConfig
                $savedLocations += "PSFConfig: $configName"
                Write-PSFMessage -Level Verbose -Message "Saved to PSF configuration: $configName"
            }
        }

        # 3. Save to file path if specified
        if ($FilePath) {
            if ($PSCmdlet.ShouldProcess($FilePath, "Save credential file")) {
                $fileDir = Split-Path $FilePath -Parent
                if ($fileDir -and -not (Test-Path $fileDir)) {
                    New-Item -ItemType Directory -Path $fileDir -Force | Out-Null
                }

                $fileContent = @{
                    token        = $Token
                    tool         = $Tool
                    configuredAt = (Get-Date -Format "o")
                }

                # For Claude, also create the CLI credentials format
                if ($Tool -eq 'Claude') {
                    # Check if this is the CLI credentials path
                    if ($FilePath -match '\.credentials\.json$') {
                        $fileContent = @{
                            claudeAiOauth = @{
                                accessToken      = $Token
                                refreshToken     = ""
                                expiresAt        = [long]([DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeMilliseconds())
                                scopes           = @("user:inference")
                                subscriptionType = "max"
                                rateLimitTier    = "default_claude_max_20x"
                            }
                        }
                    }
                }

                $fileContent | ConvertTo-Json -Depth 5 | Set-Content -Path $FilePath -Force
                $savedLocations += "File: $FilePath"
                Write-PSFMessage -Level Verbose -Message "Saved credential file: $FilePath"
            }
        }

        $result.Success = $true
        $result.Locations = $savedLocations
        $result.Message = "$Tool credentials saved to: $($savedLocations -join ', ')"
    }
    catch {
        $result.Success = $false
        $result.Locations = $savedLocations
        $result.Message = "Failed to save credentials: $($_.Exception.Message)"
        Write-PSFMessage -Level Error -Message $result.Message
    }

    return $result
}
