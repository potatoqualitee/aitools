function Invoke-AIToolSimple {
    <#
    .SYNOPSIS
        Sends a simple prompt to an AI tool and returns the response.

    .DESCRIPTION
        A simplified interface for AI tool invocation that doesn't require file processing.
        Designed for chatbot-style interactions, SQL analysis, and other prompt/response scenarios.

        Unlike Invoke-AITool which is optimized for batch file processing, this function:
        - Takes a prompt and returns the response directly
        - Supports optional system prompts for context
        - Handles credential setup automatically
        - Returns structured output with response text, duration, and token usage

    .PARAMETER Tool
        The AI tool to use. Defaults to Claude if not specified.

    .PARAMETER Prompt
        The prompt to send to the AI tool.

    .PARAMETER SystemPrompt
        Optional system prompt for context (prepended to the user prompt).

    .PARAMETER Model
        Optional model override for the AI tool.

    .PARAMETER OutputFormat
        Output format: json, text. Defaults to json.

    .PARAMETER AllowedTools
        Optional list of tools the AI can use (tool-specific whitelist).

    .PARAMETER CredentialPath
        Optional path to a credential/config file for token authentication.

    .PARAMETER MaxPromptLength
        Maximum prompt length before switching to file-based input.
        Default: 7000 characters (avoids Claude CLI empty output bug).

    .EXAMPLE
        Invoke-AIToolSimple -Prompt "Explain the concept of recursion"

    .EXAMPLE
        Invoke-AIToolSimple -Tool Claude -Prompt $sqlQuery -SystemPrompt "You are a SQL Server DBA"

    .EXAMPLE
        $result = Invoke-AIToolSimple -Prompt "What is 2+2?"
        $result.Response  # "4"

    .OUTPUTS
        PSCustomObject with:
        - Success: Boolean indicating if the call succeeded
        - Response: The AI's response text
        - DurationMs: Time taken in milliseconds
        - TokenUsage: Token counts (if available from the tool)
        - Error: Error message if Success is false
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tool = 'Claude',

        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string]$SystemPrompt,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [ValidateSet('json', 'text')]
        [string]$OutputFormat = 'json',

        [Parameter()]
        [string[]]$AllowedTools,

        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [int]$MaxPromptLength = 7000
    )

    $result = [PSCustomObject]@{
        Success    = $false
        Response   = $null
        DurationMs = 0
        TokenUsage = $null
        Error      = $null
    }

    # Resolve tool alias to canonical name
    $Tool = Resolve-ToolAlias -ToolName $Tool

    # Get tool definition
    $toolDef = $script:ToolDefinitions[$Tool]
    if (-not $toolDef) {
        $result.Error = "Unknown AI tool: $Tool"
        return $result
    }

    # Verify tool is available
    if (-not (Test-Command -Command $toolDef.Command)) {
        $result.Error = "$Tool CLI is not installed. Run Install-AITool -Tool $Tool to install it."
        return $result
    }

    # Handle credential/token setup
    $credentialSetup = Get-AIToolCredential -Tool $Tool -CredentialPath $CredentialPath
    if (-not $credentialSetup.Configured) {
        $result.Error = "$Tool credentials not configured. Use Set-AIToolCredential to configure."
        return $result
    }

    foreach ($envVar in $credentialSetup.EnvironmentVariables.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($envVar.Key, $envVar.Value, 'Process')
    }

    # Build the full prompt
    $fullPrompt = $Prompt
    if ($SystemPrompt) {
        $fullPrompt = "$SystemPrompt`n`n$Prompt"
    }

    # Determine if we need file-based input for large prompts
    $usePromptFile = $fullPrompt.Length -gt $MaxPromptLength
    $promptFile = $null

    try {
        $startTime = Get-Date

        # Build arguments based on tool
        $arguments = switch ($Tool) {
            'Claude' {
                # -p flag is REQUIRED for headless/non-interactive mode in containers
                $args = @('-p')

                if ($usePromptFile) {
                    $promptFile = [System.IO.Path]::GetTempFileName()
                    [System.IO.File]::WriteAllText($promptFile, $fullPrompt)
                    # Keep -p for headless mode AND add --prompt-file for large prompts
                    $args += '--prompt-file', $promptFile
                }
                else {
                    $args += $fullPrompt
                }

                $args += '--output-format', $OutputFormat

                if ($Model) { $args += '--model', $Model }
                if ($AllowedTools -and $AllowedTools.Count -gt 0) {
                    $args += '--allowedTools', ($AllowedTools -join ',')
                }
                $args
            }
            'Gemini' {
                $args = @('-p')
                if ($usePromptFile) {
                    $promptFile = [System.IO.Path]::GetTempFileName()
                    [System.IO.File]::WriteAllText($promptFile, $fullPrompt)
                    # Keep -p for headless mode AND add --prompt-file
                    $args += '--prompt-file', $promptFile
                }
                else {
                    $args += $fullPrompt
                }
                if ($Model) { $args += '--model', $Model }
                $args
            }
            'Aider' {
                $args = @('--message', $fullPrompt, '--no-git', '--yes')
                if ($Model) { $args += '--model', $Model }
                $args
            }
            default {
                @('-p', $fullPrompt)
            }
        }

        # Execute the tool
        Write-PSFMessage -Level Verbose -Message "Executing $Tool with arguments: $($arguments -join ' ')"

        $rawOutput = & $toolDef.Command @arguments 2>&1
        $exitCode = $LASTEXITCODE

        $duration = (Get-Date) - $startTime
        $result.DurationMs = [int]$duration.TotalMilliseconds

        if ($exitCode -ne 0) {
            $errorOutput = if ($rawOutput) { $rawOutput -join "`n" } else { "No output" }
            $result.Error = "$Tool CLI exited with code $exitCode`: $errorOutput"
            return $result
        }

        # Process output based on format
        $responseText = if ($rawOutput -is [array]) { $rawOutput -join "`n" } else { [string]$rawOutput }

        # Try to parse JSON output
        if ($OutputFormat -eq 'json' -and $responseText -match '^\s*\{') {
            try {
                $parsed = $responseText | ConvertFrom-Json
                $result.Response = $parsed.result
                if ($parsed.usage) {
                    $result.TokenUsage = @{
                        InputTokens  = $parsed.usage.input_tokens
                        OutputTokens = $parsed.usage.output_tokens
                    }
                }
            }
            catch {
                # JSON parsing failed, use raw response
                $result.Response = $responseText
            }
        }
        else {
            $result.Response = $responseText
        }

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    finally {
        # Clean up temp file
        if ($promptFile -and (Test-Path $promptFile)) {
            Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
        }
    }

    return $result
}
