function Invoke-AIToolStream {
    <#
    .SYNOPSIS
        Streams AI tool output to an HTTP response using Server-Sent Events (SSE).

    .DESCRIPTION
        Executes an AI CLI tool and streams the output in real-time to a web response object
        using the SSE (Server-Sent Events) protocol. This is designed for web API endpoints
        that need to provide streaming responses to clients.

        The function handles:
        - Setting up SSE response headers
        - Parsing tool-specific JSON streaming formats
        - Sending incremental content, tool usage, and result events
        - Error handling and completion signaling

    .PARAMETER Tool
        The AI tool to use. Defaults to Claude if not specified.

    .PARAMETER Prompt
        The prompt to send to the AI tool.

    .PARAMETER Response
        The HTTP response object to stream to (e.g., PSU $Response object).
        Must support Write() and Flush() methods.

    .PARAMETER Model
        Optional model override for the AI tool.

    .PARAMETER AllowedTools
        Optional list of tools the AI can use (tool-specific whitelist).

    .PARAMETER SystemPrompt
        Optional system prompt to prepend to the user prompt.

    .PARAMETER CredentialPath
        Optional path to a credential/config file for token authentication.
        If not specified, uses default aitools credential storage.

    .PARAMETER MaxTokens
        Optional maximum tokens for the response.

    .EXAMPLE
        Invoke-AIToolStream -Prompt "Explain this code" -Response $Response

    .EXAMPLE
        Invoke-AIToolStream -Tool Claude -Prompt $fullPrompt -Response $Response -AllowedTools @('Read', 'Grep')

    .NOTES
        Designed for use in PowerShell Universal (PSU) endpoints or similar web frameworks
        that support streaming HTTP responses.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tool = 'Claude',

        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        $Response,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string[]]$AllowedTools,

        [Parameter()]
        [string]$SystemPrompt,

        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [int]$MaxTokens
    )

    # Resolve tool alias to canonical name
    $Tool = Resolve-ToolAlias -ToolName $Tool

    # Get tool definition
    $toolDef = $script:ToolDefinitions[$Tool]
    if (-not $toolDef) {
        throw "Unknown AI tool: $Tool"
    }

    # Verify tool is available
    if (-not (Test-Command -Command $toolDef.Command)) {
        throw "$Tool CLI is not installed. Run Install-AITool -Tool $Tool to install it."
    }

    # Handle credential/token setup
    $credentialSetup = Get-AIToolCredential -Tool $Tool -CredentialPath $CredentialPath
    if ($credentialSetup.EnvironmentVariables) {
        foreach ($envVar in $credentialSetup.EnvironmentVariables.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($envVar.Key, $envVar.Value, 'Process')
        }
    }

    # Write prompt to temp file to avoid shell escaping issues
    $promptFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($promptFile, $Prompt)

        # Build arguments based on tool
        $arguments = switch ($Tool) {
            'Claude' {
                # -p flag is REQUIRED for headless/non-interactive mode in containers
                $args = @('-p', '--prompt-file', $promptFile, '--output-format', 'stream-json')
                if ($Model) { $args += '--model', $Model }
                if ($AllowedTools -and $AllowedTools.Count -gt 0) {
                    $args += '--allowedTools', ($AllowedTools -join ',')
                }
                if ($SystemPrompt) {
                    $args += '--system-prompt', $SystemPrompt
                }
                $args
            }
            'Gemini' {
                $args = @('-p', '--prompt-file', $promptFile, '--output-format', 'stream-json')
                if ($Model) { $args += '--model', $Model }
                $args
            }
            default {
                # Generic fallback - may not support streaming
                @('-p', $Prompt)
            }
        }

        # Set up SSE response headers
        $Response.ContentType = 'text/event-stream'
        $Response.Headers['Cache-Control'] = 'no-cache'
        $Response.Headers['Connection'] = 'keep-alive'
        $Response.Headers['X-Accel-Buffering'] = 'no'

        $startTime = Get-Date
        $fullResponse = ""
        $hasError = $false
        $errorMessage = ""
        $resultInfo = $null

        # Stream tool output line by line
        & $toolDef.Command @arguments 2>&1 | ForEach-Object {
            $line = $PSItem

            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop

                switch ($obj.type) {
                    'system' {
                        # System messages (session info, etc.) - log but don't send to client
                        Write-PSFMessage -Level Debug -Message "[$Tool] System: $($obj.subtype)"
                    }
                    'assistant' {
                        # Assistant message with content array
                        if ($obj.message.content) {
                            foreach ($content in $obj.message.content) {
                                switch ($content.type) {
                                    'text' {
                                        if ($content.text) {
                                            $fullResponse += $content.text
                                            $sseData = @{
                                                type = 'content'
                                                text = $content.text
                                            } | ConvertTo-Json -Compress
                                            $Response.Write("data: $sseData`n`n")
                                            $Response.Flush()
                                        }
                                    }
                                    'tool_use' {
                                        # Tool usage - send as metadata
                                        $sseData = @{
                                            type   = 'tool_use'
                                            tool   = $content.name
                                            toolId = $content.id
                                        } | ConvertTo-Json -Compress
                                        $Response.Write("data: $sseData`n`n")
                                        $Response.Flush()
                                    }
                                }
                            }
                        }
                    }
                    'user' {
                        # User turn (tool results, etc.)
                        if ($obj.message.content) {
                            foreach ($content in $obj.message.content) {
                                if ($content.type -eq 'tool_result') {
                                    $sseData = @{
                                        type    = 'tool_result'
                                        toolId  = $content.tool_use_id
                                        isError = [bool]$content.is_error
                                    } | ConvertTo-Json -Compress
                                    $Response.Write("data: $sseData`n`n")
                                    $Response.Flush()
                                }
                            }
                        }
                    }
                    'result' {
                        # Final result with stats
                        $resultInfo = @{
                            durationMs   = $obj.duration_ms
                            totalCost    = $obj.total_cost_usd
                            inputTokens  = $obj.usage.input_tokens
                            outputTokens = $obj.usage.output_tokens
                        }
                        # result.result contains the final text if present
                        if ($obj.result -and -not $fullResponse) {
                            $fullResponse = $obj.result
                        }
                    }
                }
            }
            catch {
                # Not JSON - could be stderr or other output
                $lineStr = [string]$line
                if ($lineStr -and $lineStr.Trim()) {
                    Write-PSFMessage -Level Debug -Message "[$Tool] Raw: $lineStr"
                    # Check if it looks like an error
                    if ($lineStr -match 'error|failed|exception' -and -not $lineStr.StartsWith('{')) {
                        $hasError = $true
                        $errorMessage = $lineStr
                    }
                }
            }
        }

        $duration = (Get-Date) - $startTime

        # Check exit code
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $hasError = $true
            $errorMessage = "$Tool CLI exited with code $exitCode"
        }

        # Send error if no content and has error
        if ($hasError -or (-not $fullResponse -and -not $resultInfo)) {
            $errMsg = if ($errorMessage) { $errorMessage } else { "No response received from $Tool CLI. Check configuration." }
            $errorData = @{
                type    = 'error'
                message = $errMsg
            } | ConvertTo-Json -Compress
            $Response.Write("data: $errorData`n`n")
        }

        # Send completion event
        $doneData = @{
            type       = 'done'
            durationMs = if ($resultInfo) { $resultInfo.durationMs } else { [int]$duration.TotalMilliseconds }
            totalCost  = if ($resultInfo) { $resultInfo.totalCost } else { $null }
        } | ConvertTo-Json -Compress
        $Response.Write("data: $doneData`n`n")
        $Response.Flush()
    }
    catch {
        Write-PSFMessage -Level Error -Message "[$Tool STREAM] Exception: $($PSItem.Exception.Message)"
        $errorData = @{
            type    = 'error'
            message = $PSItem.Exception.Message
        } | ConvertTo-Json -Compress
        $Response.Write("data: $errorData`n`n")
        $Response.Flush()
    }
    finally {
        # Clean up temp file
        if (Test-Path $promptFile) {
            Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
        }
    }
}
