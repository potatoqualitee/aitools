function Invoke-StreamingExecution {
    <#
    .SYNOPSIS
        Executes an AI tool with streaming output to console.
    .DESCRIPTION
        Handles real-time streaming of AI tool output. For tools with JSON streaming
        (Claude, Gemini), parses the stream-json format and extracts text content.
        For other tools, pipes output directly to console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$ToolCommand,

        [Parameter()]
        [string[]]$Arguments,

        [Parameter()]
        [string]$FullPrompt,

        [Parameter()]
        [string]$Context = "Streaming operation"
    )

    $startTime = Get-Date
    $streamedContent = [System.Text.StringBuilder]::new()

    $originalOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        # Determine execution style based on tool
        $usesPipedInput = $ToolName -notin @('Aider', 'Codex', 'Cursor')

        if ($usesPipedInput -and $FullPrompt) {
            $process = $FullPrompt | & $ToolCommand @Arguments 2>&1
        } else {
            $process = & $ToolCommand @Arguments 2>&1
        }

        $process | ForEach-Object {
            $line = $_
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                Write-PSFMessage -Level Debug -Message $line.Exception.Message
            } elseif ($ToolName -in @('Claude', 'Gemini') -and $line -match '^\s*\{') {
                # Try to parse as JSON streaming event
                try {
                    $jsonEvent = $line | ConvertFrom-Json -ErrorAction Stop

                    # Handle Claude CLI stream-json format (complete JSON objects per line)
                    switch ($jsonEvent.type) {
                        'system' {
                            # Init event - show model info
                            if ($jsonEvent.subtype -eq 'init' -and $jsonEvent.model) {
                                Write-Host "[" -NoNewline
                                Write-Host $jsonEvent.model -ForegroundColor DarkCyan -NoNewline
                                Write-Host "]" -NoNewline
                                Write-Host ""
                            }
                        }
                        'assistant' {
                            # Message with content - can be text or tool_use
                            if ($jsonEvent.message.content) {
                                foreach ($block in $jsonEvent.message.content) {
                                    if ($block.type -eq 'text') {
                                        Write-Host $block.text -NoNewline
                                        $null = $streamedContent.Append($block.text)
                                    } elseif ($block.type -eq 'tool_use') {
                                        # Show tool usage with summary
                                        Write-Host "`n[" -NoNewline
                                        Write-Host $block.name -ForegroundColor Cyan -NoNewline
                                        Write-Host "] " -NoNewline

                                        # Show relevant info based on tool type
                                        $summary = switch -Wildcard ($block.name) {
                                            'Read' { if ($block.input.file_path) { $block.input.file_path } else { "file" } }
                                            'Edit' { if ($block.input.file_path) { $block.input.file_path } else { "file" } }
                                            'Write' { if ($block.input.file_path) { $block.input.file_path } else { "file" } }
                                            'Bash' {
                                                if ($block.input.command) {
                                                    $cmd = $block.input.command
                                                    $cmd.Substring(0, [Math]::Min(60, $cmd.Length)) + $(if ($cmd.Length -gt 60) { "..." } else { "" })
                                                } else { "command" }
                                            }
                                            'Glob' { if ($block.input.pattern) { $block.input.pattern } else { "pattern" } }
                                            'Grep' { if ($block.input.pattern) { $block.input.pattern } else { "pattern" } }
                                            'Task' { if ($block.input.description) { $block.input.description } else { "task" } }
                                            'TodoWrite' { "updating todos" }
                                            default { "" }
                                        }
                                        if ($summary) {
                                            Write-Host $summary -ForegroundColor DarkGray
                                        } else {
                                            Write-Host ""
                                        }
                                    }
                                }
                            }
                        }
                        'user' {
                            # Tool result - show brief indicator
                            if ($jsonEvent.tool_use_result) {
                                Write-Host "  [" -NoNewline
                                Write-Host "done" -ForegroundColor Green -NoNewline
                                Write-Host "]" -NoNewline
                            }
                        }
                        'result' {
                            # Final result
                            Write-Host ""
                            if ($jsonEvent.subtype -eq 'success') {
                                Write-Host "[" -NoNewline
                                Write-Host "completed" -ForegroundColor Green -NoNewline
                                Write-Host "] " -NoNewline
                                if ($jsonEvent.duration_ms) {
                                    $secs = [Math]::Round($jsonEvent.duration_ms / 1000, 1)
                                    Write-Host "${secs}s" -ForegroundColor DarkGray
                                }
                            } elseif ($jsonEvent.subtype -eq 'error') {
                                Write-Host "[" -NoNewline
                                Write-Host "error" -ForegroundColor Red -NoNewline
                                Write-Host "] " -NoNewline
                                if ($jsonEvent.result) {
                                    Write-Host $jsonEvent.result -ForegroundColor Red
                                }
                            }
                        }
                        default {
                            # Check for Gemini format or other content
                            if ($jsonEvent.content) {
                                Write-Host $jsonEvent.content -NoNewline
                                $null = $streamedContent.Append($jsonEvent.content)
                            }
                        }
                    }
                } catch {
                    # Not valid JSON, output as-is
                    Write-Host $line
                    $null = $streamedContent.AppendLine($line)
                }
            } else {
                # Non-JSON output, display directly
                Write-Host $line
                $null = $streamedContent.AppendLine($line)
            }
        }

        $exitCode = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $originalOutputEncoding
    }

    $endTime = Get-Date
    @{
        Output   = $streamedContent.ToString()
        ExitCode = $exitCode
        Success  = ($exitCode -eq 0)
        Duration = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
    }
}
