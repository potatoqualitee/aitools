function Invoke-ChatMode {
    <#
    .SYNOPSIS
        Handles chat-only mode (no files specified) for AI tools.

    .DESCRIPTION
        Executes an AI tool in chat mode when no input files are provided.
        Builds the prompt with context files, handles tool-specific argument
        building, and manages output capture or raw mode.

    .PARAMETER ToolName
        The name of the AI tool to use.

    .PARAMETER ToolDefinition
        The tool definition hashtable containing Command and other properties.

    .PARAMETER PromptText
        The prompt text to send.

    .PARAMETER ContextFiles
        Array of context file paths to include.

    .PARAMETER Model
        The model to use.

    .PARAMETER ReasoningEffort
        The reasoning effort level for supported tools.

    .PARAMETER PermissionBypass
        Whether to bypass permission prompts.

    .PARAMETER IgnoreInstructions
        Whether to ignore instruction files.

    .PARAMETER EditMode
        The edit mode for Aider.

    .PARAMETER ImageAttachments
        Array of image attachment paths for Codex.

    .PARAMETER PromptFilePath
        The original prompt file path for Copilot.

    .PARAMETER Raw
        If specified, runs in raw mode without capturing output.

    .PARAMETER DisableRetry
        Disable automatic retry.

    .PARAMETER MaxRetryMinutes
        Maximum retry time in minutes.

    .PARAMETER OriginalLocation
        The original location to restore after execution.

    .OUTPUTS
        [PSCustomObject] result object (unless in Raw mode).

    .EXAMPLE
        Invoke-ChatMode -ToolName "Claude" -ToolDefinition $toolDef -PromptText "Hello"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [hashtable]$ToolDefinition,

        [Parameter(Mandatory)]
        [string]$PromptText,

        [Parameter()]
        [string[]]$ContextFiles,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$ReasoningEffort,

        [Parameter()]
        [bool]$PermissionBypass = $true,

        [Parameter()]
        [bool]$IgnoreInstructions = $false,

        [Parameter()]
        [string]$EditMode = 'Diff',

        [Parameter()]
        [string[]]$ImageAttachments,

        [Parameter()]
        [string]$PromptFilePath,

        [Parameter()]
        [switch]$Raw,

        [Parameter()]
        [switch]$DisableRetry,

        [Parameter()]
        [int]$MaxRetryMinutes = 240,

        [Parameter()]
        [string]$OriginalLocation
    )

    Write-PSFMessage -Level Verbose -Message "No files specified - entering chat-only mode"

    # Build combined prompt with context files
    $fullPrompt = $PromptText
    if ($ContextFiles -and $ContextFiles.Count -gt 0) {
        Write-PSFMessage -Level Verbose -Message "Building combined prompt with $($ContextFiles.Count) context file(s)"
        foreach ($ctxFile in $ContextFiles) {
            if (Test-Path $ctxFile) {
                $content = Get-Content -Path $ctxFile -Raw
                $fullPrompt += "`n`n--- Context from $($ctxFile) ---`n$content"
                Write-PSFMessage -Level Verbose -Message "Added context from: $ctxFile"
            } else {
                Write-PSFMessage -Level Warning -Message "Context file not found: $ctxFile"
            }
        }

        # If context is a single JSON file, append instruction for raw JSON output
        $existingContextFiles = @($ContextFiles | Where-Object { Test-Path $_ })
        if ($existingContextFiles.Count -eq 1) {
            $singleContextFile = $existingContextFiles[0]
            if ([System.IO.Path]::GetExtension($singleContextFile).ToLower() -eq '.json') {
                $fullPrompt += "`n`nIMPORTANT: Output raw JSON only - no markdown code fences, no backticks, no explanation. Response must start with { and end with } for direct parsing by ConvertFrom-Json."
                Write-PSFMessage -Level Verbose -Message "Single JSON context detected - added raw JSON output instruction"
            }
        }
    }

    # Add Claude reasoning trigger if needed
    if ($ToolName -eq 'Claude' -and $ReasoningEffort) {
        $reasoningPhrase = switch ($ReasoningEffort) {
            'low'    { 'think hard' }
            'medium' { 'think harder' }
            'high'   { 'ultrathink' }
        }
        $fullPrompt += "`n`n$reasoningPhrase"
        Write-PSFMessage -Level Verbose -Message "Claude reasoning trigger appended: $reasoningPhrase"
    }

    Write-PSFMessage -Level Verbose -Message "Building arguments for chat mode with $ToolName"

    # Build tool-specific arguments
    $arguments = switch ($ToolName) {
        'Claude' {
            $argumentParams = @{
                Message             = $fullPrompt
                Model               = $Model
                UsePermissionBypass = $PermissionBypass
                IgnoreInstructions  = $IgnoreInstructions
            }
            if ($ReasoningEffort) {
                $argumentParams['ReasoningEffort'] = $ReasoningEffort
            }
            New-ClaudeArgument @argumentParams
        }
        'Aider' {
            $argumentParams = @{
                Message             = $fullPrompt
                Model               = $Model
                EditMode            = $EditMode
                ContextFiles        = $ContextFiles
                UsePermissionBypass = $PermissionBypass
            }
            if ($ReasoningEffort) {
                $argumentParams['ReasoningEffort'] = $ReasoningEffort
            }
            New-AiderArgument @argumentParams
        }
        'Gemini' {
            $argumentParams = @{
                Message             = $fullPrompt
                Model               = $Model
                UsePermissionBypass = $PermissionBypass
            }
            New-GeminiArgument @argumentParams
        }
        'Copilot' {
            $argumentParams = @{
                Message             = $fullPrompt
                Model               = $Model
                UsePermissionBypass = $PermissionBypass
                IgnoreInstructions  = $IgnoreInstructions
                WorkingDirectory    = (Get-Location).Path
                PromptFilePath      = $PromptFilePath
                ContextFilePaths    = $ContextFiles
            }
            New-CopilotArgument @argumentParams
        }
        'Codex' {
            $argumentParams = @{
                Message             = $fullPrompt
                Model               = $Model
                UsePermissionBypass = $PermissionBypass
                WorkingDirectory    = (Get-Location).Path
            }
            if ($ReasoningEffort) {
                $argumentParams['ReasoningEffort'] = $ReasoningEffort
            }
            if ($ImageAttachments -and $ImageAttachments.Count -gt 0) {
                $argumentParams['Attachment'] = $ImageAttachments
            }
            New-CodexArgument @argumentParams
        }
        'Cursor' {
            $argumentParams = @{
                Message             = $fullPrompt
                Model               = $Model
                ContextFiles        = $ContextFiles
                UsePermissionBypass = $PermissionBypass
            }
            if ($ReasoningEffort) {
                $argumentParams['ReasoningEffort'] = $ReasoningEffort
            }
            New-CursorArgument @argumentParams
        }
        'Ollama' {
            $argumentParams = @{
                Message             = $fullPrompt
                Model               = $Model
                UsePermissionBypass = $PermissionBypass
            }
            New-OllamaArgument @argumentParams
        }
    }

    Write-PSFMessage -Level Verbose -Message "Executing chat mode: $($ToolDefinition.Command) $($arguments -join ' ')"

    $startTime = Get-Date

    try {
        if ($Raw) {
            Write-PSFMessage -Level Verbose -Message "Executing in raw mode (no output capturing)"

            if ($ToolName -eq 'Aider') {
                $originalOutputEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                $env:PYTHONIOENCODING = 'utf-8'
                $env:LITELLM_NUM_RETRIES = '0'

                & $ToolDefinition.Command @arguments 2>&1 | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord]) {
                        Write-PSFMessage -Level Debug -Message $_.Exception.Message
                    } else {
                        $_
                    }
                }

                [Console]::OutputEncoding = $originalOutputEncoding
                Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
            } elseif ($ToolName -eq 'Codex') {
                $originalOutputEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

                & $ToolDefinition.Command @arguments 2>&1 | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord]) {
                        Write-PSFMessage -Level Debug -Message $_.Exception.Message
                    } else {
                        $_
                    }
                }

                [Console]::OutputEncoding = $originalOutputEncoding
            } else {
                $originalOutputEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

                $fullPrompt | & $ToolDefinition.Command @arguments 2>&1 | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord]) {
                        Write-PSFMessage -Level Debug -Message $_.Exception.Message
                    } else {
                        $_
                    }
                }

                [Console]::OutputEncoding = $originalOutputEncoding
            }

            $exitCode = $LASTEXITCODE
            Write-PSFMessage -Level Verbose -Message "Tool exited with code: $exitCode"

            if ($exitCode -eq 0) {
                Write-PSFMessage -Level Verbose -Message "Command completed successfully"
            } else {
                Write-PSFMessage -Level Warning -Message "Command failed with exit code $exitCode"
            }

            return
        }

        # Captured mode
        $tempOutputFile = [System.IO.Path]::GetTempFileName()
        Write-PSFMessage -Level Verbose -Message "Redirecting output to temp file: $tempOutputFile"

        $capturedOutput = $null
        $toolExitCode = 0

        if ($ToolName -eq 'Aider') {
            Write-PSFMessage -Level Verbose -Message "Executing Aider in chat mode with native --read context files"
            $originalOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $env:PYTHONIOENCODING = 'utf-8'
            $env:LITELLM_NUM_RETRIES = '0'

            $executionScriptBlock = {
                $outFileParams = @{
                    FilePath = $tempOutputFile
                    Encoding = 'utf8'
                }
                & $ToolDefinition.Command @arguments *>&1 | Tee-Object @outFileParams
            }.GetNewClosure()

            $capturedOutput = Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Aider chat mode"
            $toolExitCode = $LASTEXITCODE

            Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

            if ($capturedOutput -is [array]) {
                $capturedOutput = $capturedOutput | Out-String
            }

            [Console]::OutputEncoding = $originalOutputEncoding
            Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue

        } elseif ($ToolName -eq 'Codex') {
            Write-PSFMessage -Level Verbose -Message "Executing Codex in chat mode (prompt in arguments)"

            $executionScriptBlock = [ScriptBlock]::Create(@"
& '$($ToolDefinition.Command)' $($arguments | ForEach-Object { if ($_ -match '\s') { "'$($_.Replace("'", "''"))'" } else { $_ } }) *>&1 | Out-File -FilePath '$tempOutputFile' -Encoding utf8
"@)

            Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Codex chat mode"
            $toolExitCode = $LASTEXITCODE

            $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
            Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

        } elseif ($ToolName -eq 'Cursor') {
            Write-PSFMessage -Level Verbose -Message "Executing Cursor in chat mode (prompt in arguments)"

            $executionScriptBlock = {
                & $ToolDefinition.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
            }.GetNewClosure()

            Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Cursor chat mode"
            $toolExitCode = $LASTEXITCODE

            $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
            Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

        } else {
            Write-PSFMessage -Level Verbose -Message "Piping prompt to $ToolName in chat mode"

            $executionScriptBlock = {
                $fullPrompt | & $ToolDefinition.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
            }.GetNewClosure()

            Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$ToolName chat mode"
            $toolExitCode = $LASTEXITCODE

            $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
            Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

            # Filter out misleading Gemini warnings and informational stderr messages
            if ($ToolName -eq 'Gemini') {
                $capturedOutput = $capturedOutput -replace '(?m)^\s*\[WARN\]\s+Skipping unreadable directory:.*?\n', ''
                # Filter out informational messages that Gemini CLI writes to stderr
                $capturedOutput = $capturedOutput -replace '(?m)^.*YOLO mode is enabled\..*\n?', ''
                $capturedOutput = $capturedOutput -replace '(?m)^.*All tool calls will be automatically approved\..*\n?', ''
                $capturedOutput = $capturedOutput -replace '(?m)^.*Loaded cached credentials\..*\n?', ''
            }
        }

        # Determine filename/path for output
        $outputFileName = if ($ToolName -eq 'Codex' -and $ImageAttachments -and $ImageAttachments.Count -gt 0) {
            [System.IO.Path]::GetFileName($ImageAttachments[0])
        } else {
            'N/A (Chat Mode)'
        }
        $outputFullPath = if ($ToolName -eq 'Codex' -and $ImageAttachments -and $ImageAttachments.Count -gt 0) {
            $ImageAttachments[0]
        } else {
            'N/A (Chat Mode)'
        }

        $endTime = Get-Date

        # Return result object
        [PSCustomObject]@{
            FileName  = $outputFileName
            FullPath  = $outputFullPath
            Tool      = $ToolName
            Model     = if ($Model) { $Model } else { 'Default' }
            Result    = $capturedOutput
            StartTime = $startTime
            EndTime   = $endTime
            Duration  = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
            Success   = ($toolExitCode -eq 0)
        }

        Write-PSFMessage -Level Verbose -Message "Tool exited with code: $toolExitCode"
        if ($toolExitCode -eq 0) {
            $modeDesc = if ($ToolName -eq 'Codex' -and $ImageAttachments -and $ImageAttachments.Count -gt 0) { "image processing" } else { "chat mode" }
            Write-PSFMessage -Level Verbose -Message "$ToolName $modeDesc completed successfully"
        } else {
            $modeDesc = if ($ToolName -eq 'Codex' -and $ImageAttachments -and $ImageAttachments.Count -gt 0) { "image processing" } else { "chat mode" }
            Write-PSFMessage -Level Error -Message "$ToolName $modeDesc failed (exit code $toolExitCode)"
        }

    } catch {
        Write-PSFMessage -Level Error -Message "Error in chat mode: $_"
    } finally {
        if ($ToolName -eq 'Codex') {
            Write-PSFMessage -Level Verbose -Message "Cleaning up RUST_LOG environment variable"
            if (Test-Path Env:RUST_LOG) {
                Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
            }
        }

        # Restore original location
        if ($OriginalLocation) {
            Set-Location $OriginalLocation
            Write-PSFMessage -Level Verbose -Message "Restored location to: $OriginalLocation"
        }
    }
}
