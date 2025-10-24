function Invoke-AITool {
    <#
    .SYNOPSIS
        Invokes an AI CLI tool to process files with a prompt.

    .DESCRIPTION
        The primary command for batch processing files using AI CLI tools.
        Supports pipeline input for processing multiple files.

    .PARAMETER Tool
        The AI tool to use. If not specified, uses the configured default tool.

    .PARAMETER Prompt
        The instruction/prompt for the AI tool. Can be a string or a FileInfo object from Get-ChildItem.
        If a file is provided, its content will be read automatically.

    .PARAMETER Path
        File path(s) to process. Accepts pipeline input. Optional - if omitted, enters chat-only mode.

    .PARAMETER Context
        Additional files to include as read-only context. Can be strings, file paths,
        or FileInfo objects from Get-ChildItem. File contents will be read automatically.

    .PARAMETER Model
        The AI model to use. Overrides configured default.

    .PARAMETER ReasoningEffort
        The reasoning effort level to use (low, medium, high). Only supported by certain models like Codex and Aider.
        Overrides configured default.

    .PARAMETER Attachment
        Optional image file(s) to attach to the prompt. Only supported by Codex.
        Accepts common image formats (png, jpg, jpeg, gif, bmp, webp, svg).

    .PARAMETER Raw
        Run the command directly without capturing output or assigning to variables.
        Useful for interactive scenarios like Jupyter notebooks where output handling can cause issues.

    .EXAMPLE
        Get-ChildItem *.Tests.ps1 | Invoke-AITool -Prompt "Refactor from Pester v4 to v5"

    .EXAMPLE
        Invoke-AITool -Path "MyFile.ps1" -Prompt "Add help documentation" -Tool ClaudeCode -Verbose

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Fix style" -Context "StyleGuide.md" -Tool Aider -Debug

    .EXAMPLE
        Invoke-AITool -Path "MyFile.ps1" -Prompt (Get-ChildItem prompts\style.md) -Tool Aider

    .EXAMPLE
        $contextFiles = Get-ChildItem *.md
        Invoke-AITool -Path "test.ps1" -Prompt "Fix code" -Context $contextFiles -Tool Aider

    .EXAMPLE
        Invoke-AITool -Prompt "How do I implement error handling in PowerShell?" -Tool ClaudeCode

    .EXAMPLE
        Invoke-AITool -Path "complex.ps1" -Prompt "Optimize this code" -Tool Codex -ReasoningEffort high

    .EXAMPLE
        Invoke-AITool -Path "script.ps1" -Prompt "Add error handling" -Tool All
        Runs the same prompt against all installed tools sequentially.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [Alias('Name')]
        [string]$Tool,
        [Parameter(Mandatory)]
        [object]$Prompt,
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,
        [Parameter()]
        [object[]]$Context,
        [Parameter()]
        [string]$Model,
        [Parameter()]
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort,
        [Parameter()]
        [string[]]$Attachment,
        [Parameter()]
        [switch]$Raw
    )

    begin {
        # Save original location for cleanup in finally block
        $script:originalLocation = Get-Location
        Write-PSFMessage -Level Verbose -Message "Saved original location: $script:originalLocation"

        # Validate Attachment parameter - only Codex supports attachments
        if ($Attachment) {
            # Determine the effective tool (considering default)
            $effectiveTool = if ($Tool) { $Tool } else { Get-PSFConfigValue -FullName 'AITools.DefaultTool' -Fallback $null }

            if ($effectiveTool -ne 'Codex') {
                Stop-PSFFunction -Message "Attachment parameter is only supported by Codex. Current tool: $effectiveTool" -EnableException $true
                return
            }

            # Validate that all attachments have valid image extensions
            $validImageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg')
            foreach ($attachmentPath in $Attachment) {
                $extension = [System.IO.Path]::GetExtension($attachmentPath).ToLower()
                if ($extension -notin $validImageExtensions) {
                    Stop-PSFFunction -Message "Invalid attachment file type: $attachmentPath. Only image files are supported: $($validImageExtensions -join ', ')" -EnableException $true
                    return
                }

                # Verify the file exists
                if (-not (Test-Path $attachmentPath)) {
                    Stop-PSFFunction -Message "Attachment file not found: $attachmentPath" -EnableException $true
                    return
                }
            }

            Write-PSFMessage -Level Verbose -Message "Validated $($Attachment.Count) attachment(s)"
        }

        # Process Prompt parameter - detect if it's a file object or string
        $promptText = if ($Prompt -is [System.IO.FileInfo] -or $Prompt -is [System.IO.FileSystemInfo]) {
            Write-PSFMessage -Level Verbose -Message "Prompt is a file object: $($Prompt.FullName)"
            if (Test-Path $Prompt.FullName) {
                Get-Content $Prompt.FullName -Raw
            } else {
                Stop-PSFFunction -Message "Prompt file not found: $($Prompt.FullName)" -EnableException $true
                return
            }
        } elseif ($Prompt -is [string]) {
            # Check if it's a file path
            if ((Test-Path $Prompt -ErrorAction SilentlyContinue) -and -not (Test-Path $Prompt -PathType Container)) {
                Write-PSFMessage -Level Verbose -Message "Prompt is a file path: $Prompt"
                Get-Content $Prompt -Raw
            } else {
                Write-PSFMessage -Level Verbose -Message "Prompt is a plain string"
                $Prompt
            }
        } else {
            Write-PSFMessage -Level Verbose -Message "Prompt is an object, converting to string"
            $Prompt.ToString()
        }

        # Process Context parameter - detect if it's file objects or strings
        $contextFiles = @()
        if ($Context) {
            foreach ($contextItem in $Context) {
                if ($contextItem -is [System.IO.FileInfo] -or $contextItem -is [System.IO.FileSystemInfo]) {
                    Write-PSFMessage -Level Verbose -Message "Context item is a file object: $($contextItem.FullName)"
                    if (Test-Path $contextItem.FullName) {
                        # Normalize path to use forward slashes
                        $normalizedContext = $contextItem.FullName -replace '\\', '/'
                        $contextFiles += $normalizedContext
                    } else {
                        Write-PSFMessage -Level Warning -Message "Context file not found: $($contextItem.FullName)"
                    }
                } elseif ($contextItem -is [string]) {
                    # Resolve the path if it exists
                    $resolvedContext = Resolve-Path -Path $contextItem -ErrorAction SilentlyContinue
                    if ($resolvedContext) {
                        # Normalize path to use forward slashes
                        $normalizedContext = $resolvedContext.Path -replace '\\', '/'
                        Write-PSFMessage -Level Verbose -Message "Context item resolved to: $normalizedContext"
                        $contextFiles += $normalizedContext
                    } else {
                        Write-PSFMessage -Level Warning -Message "Context path not found: $contextItem"
                    }
                } else {
                    Write-PSFMessage -Level Verbose -Message "Context item is an object, attempting to get FullName or Path property"
                    if ($contextItem.PSObject.Properties['FullName']) {
                        # Normalize path to use forward slashes
                        $normalizedContext = $contextItem.FullName -replace '\\', '/'
                        $contextFiles += $normalizedContext
                    } elseif ($contextItem.PSObject.Properties['Path']) {
                        # Normalize path to use forward slashes
                        $normalizedContext = $contextItem.Path -replace '\\', '/'
                        $contextFiles += $normalizedContext
                    } else {
                        Write-PSFMessage -Level Warning -Message "Could not determine path from context object: $($contextItem.GetType().Name)"
                    }
                }
            }
        }

        # Use default tool if not specified
        if (-not $Tool) {
            Write-PSFMessage -Level Verbose -Message "No tool specified, checking for default"
            $Tool = Get-PSFConfigValue -FullName 'AITools.DefaultTool' -Fallback $null
            if (-not $Tool) {
                Stop-PSFFunction -Message "No tool specified and no default tool configured. Run Initialize-AIToolDefault or specify -Tool parameter." -EnableException $true
                return
            }
            Write-PSFMessage -Level Verbose -Message "Using default tool: $Tool"
        }

        Write-PSFMessage -Level Verbose -Message "Starting Invoke-AITool with tool: $Tool"

        # Handle "All" tool selection - get all available tools
        $toolsToRun = @()
        if ($currentTool -eq 'All') {
            Write-PSFMessage -Level Verbose -Message "Tool is 'All' - will run all available tools"
            # Get all tool names sorted by priority
            $toolsToRun = $script:ToolDefinitions.GetEnumerator() |
                Sort-Object { $_.Value.Priority } |
                Where-Object { Test-Command -Command $_.Value.Command } |
                Select-Object -ExpandProperty Key

            if ($toolsToRun.Count -eq 0) {
                Stop-PSFFunction -Message "No tools are installed. Run Install-AITool to install at least one tool." -EnableException $true
                return
            }

            Write-PSFMessage -Level Verbose -Message "Available tools to run: $($toolsToRun -join ', ')"
        } else {
            $toolsToRun = @($Tool)
        }

        $filesToProcess = @()
    }

    process {
        foreach ($file in $Path) {
            $resolvedPath = Resolve-Path -Path $file -ErrorAction SilentlyContinue
            if ($resolvedPath) {
                # Normalize path to use forward slashes for cross-platform CLI compatibility
                $normalizedPath = $resolvedPath.Path -replace '\\', '/'
                $filesToProcess += $normalizedPath
                Write-PSFMessage -Level Verbose -Message "Queued file: $normalizedPath"
            } else {
                Write-PSFMessage -Level Warning -Message "File not found: $file"
            }
        }
    }

    end {
        # Loop through each tool (will be one tool or multiple if "All" was selected)
        foreach ($currentTool in $toolsToRun) {
            Write-PSFMessage -Level Verbose -Message "Processing with tool: $currentTool"

            # Get tool definition and validate installation
            $toolDef = $script:ToolDefinitions[$currentTool]
            if (-not (Test-Command -Command $toolDef.Command)) {
                Write-PSFMessage -Level Warning -Message "$currentTool is not installed. Skipping. Run: Install-AITool -Name $currentTool"
                continue
            }

            # Load configuration for current tool
            $permissionBypass = Get-PSFConfigValue -FullName "AITools.$currentTool.PermissionBypass" -Fallback $true
            Write-PSFMessage -Level Verbose -Message "Permission bypass: $permissionBypass"

            $configuredModel = Get-PSFConfigValue -FullName "AITools.$currentTool.Model" -Fallback $null
            Write-PSFMessage -Level Verbose -Message "Configured model: $configuredModel"

            $editMode = Get-PSFConfigValue -FullName "AITools.$currentTool.EditMode" -Fallback 'Diff'
            Write-PSFMessage -Level Verbose -Message "Edit mode: $editMode"

            $configuredReasoningEffort = Get-PSFConfigValue -FullName "AITools.$currentTool.ReasoningEffort" -Fallback $null
            Write-PSFMessage -Level Verbose -Message "Configured reasoning effort: $configuredReasoningEffort"

            $modelToUse = if ($Model) { $Model } else { $configuredModel }
            Write-PSFMessage -Level Verbose -Message "Model to use: $modelToUse"

            $reasoningEffortToUse = if ($ReasoningEffort) { $ReasoningEffort } else { $configuredReasoningEffort }
            Write-PSFMessage -Level Verbose -Message "Reasoning effort to use: $reasoningEffortToUse"

            if ($filesToProcess.Count -eq 0) {
                Write-PSFMessage -Level Verbose -Message "No files specified - entering chat-only mode"

                # Build combined prompt with context files for chat mode
                $fullPrompt = $promptText
                if ($contextFiles.Count -gt 0) {
                    Write-PSFMessage -Level Verbose -Message "Building combined prompt with $($contextFiles.Count) context file(s)"
                    foreach ($ctxFile in $contextFiles) {
                        if (Test-Path $ctxFile) {
                            $content = Get-Content -Path $ctxFile -Raw
                            $fullPrompt += "`n`n--- Context from $($ctxFile) ---`n$content"
                            Write-PSFMessage -Level Verbose -Message "Added context from: $ctxFile"
                        } else {
                            Write-PSFMessage -Level Warning -Message "Context file not found: $ctxFile"
                        }
                    }
                }

                # Add ClaudeCode reasoning trigger if needed
                if ($currentTool -eq 'ClaudeCode' -and $reasoningEffortToUse) {
                    $reasoningPhrase = switch ($reasoningEffortToUse) {
                        'low'    { 'think hard' }
                        'medium' { 'think harder' }
                        'high'   { 'ultrathink' }
                    }
                    Write-PSFMessage -Level Verbose -Message "Adding ClaudeCode reasoning trigger: $reasoningPhrase"
                    $fullPrompt += "`n`n$reasoningPhrase"
                }

                Write-PSFMessage -Level Verbose -Message "Building arguments for chat mode with $currentTool"
                $arguments = switch ($currentTool) {
                'ClaudeCode' {
                    $argumentParams = @{
                        Message             = $fullPrompt
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    New-ClaudeArgument @argumentParams
                }
                'Aider' {
                    $argumentParams = @{
                        Message             = $fullPrompt
                        Model               = $modelToUse
                        EditMode            = $editMode
                        ContextFiles        = $contextFiles
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    New-AiderArgument @argumentParams
                }
                'Gemini' {
                    $argumentParams = @{
                        Message             = $fullPrompt
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    New-GeminiArgument @argumentParams
                }
                'GitHubCopilot' {
                    $argumentParams = @{
                        Message             = $fullPrompt
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        WorkingDirectory    = (Get-Location).Path
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    New-CopilotArgument @argumentParams
                }
                'Codex' {
                    $argumentParams = @{
                        Message             = $fullPrompt
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        WorkingDirectory    = (Get-Location).Path
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    if ($Attachment) {
                        $argumentParams['Attachment'] = $Attachment
                    }
                    New-CodexArgument @argumentParams
                }
                'Cursor' {
                    $argumentParams = @{
                        Message             = $fullPrompt
                        Model               = $modelToUse
                        ContextFiles        = $contextFiles
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    New-CursorArgument @argumentParams
                }
            }

                Write-PSFMessage -Level Verbose -Message "Executing chat mode: $($toolDef.Command) $($arguments -join ' ')"

                $startTime = Get-Date

                try {
                    if ($Raw) {
                        Write-PSFMessage -Level Verbose -Message "Executing in raw mode (no output capturing)"
                        if ($currentTool -eq 'Aider') {
                        $originalOutputEncoding = [Console]::OutputEncoding
                        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                        $env:PYTHONIOENCODING = 'utf-8'

                        & $toolDef.Command @arguments 2>&1 | ForEach-Object {
                            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                                Write-PSFMessage -Level Debug -Message $_.Exception.Message
                            } else {
                                $_
                            }
                        }

                        [Console]::OutputEncoding = $originalOutputEncoding
                        Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
                    } elseif ($currentTool -eq 'Codex') {
                        # Codex receives prompt as command-line argument, no piping needed
                        $originalOutputEncoding = [Console]::OutputEncoding
                        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

                        & $toolDef.Command @arguments 2>&1 | ForEach-Object {
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

                        $fullPrompt | & $toolDef.Command @arguments 2>&1 | ForEach-Object {
                            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                                Write-PSFMessage -Level Debug -Message $_.Exception.Message
                            } else {
                                $_
                            }
                        }

                        [Console]::OutputEncoding = $originalOutputEncoding
                    }

                    # Provide user-friendly feedback based on exit code
                    $exitCode = $LASTEXITCODE
                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $exitCode"

                    if ($exitCode -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Command completed successfully"
                    } else {
                        Write-PSFMessage -Level Warning -Message "Command failed with exit code $exitCode"
                        Write-PSFMessage -Level Verbose -Message "Note: Some tools write debug/warning messages to stderr even on success. Check the output above to determine if there was a real error."
                    }

                    return
                }

                # Create temp file for output redirection (allows tool to run natively while capturing output)
                $tempOutputFile = [System.IO.Path]::GetTempFileName()
                Write-PSFMessage -Level Verbose -Message "Redirecting output to temp file: $tempOutputFile"

                # Output structured object to pipeline with file-based output capture
                if ($currentTool -eq 'Aider') {
                    Write-PSFMessage -Level Verbose -Message "Executing Aider in chat mode with native --read context files"
                    $originalOutputEncoding = [Console]::OutputEncoding
                    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                    $env:PYTHONIOENCODING = 'utf-8'

                    # Redirect to temp file instead of capturing directly
                    & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        FileName     = 'N/A (Chat Mode)'
                        FullPath     = 'N/A (Chat Mode)'
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Chat mode completed successfully"
                    } else {
                        Write-PSFMessage -Level Error -Message "Chat mode failed (exit code $LASTEXITCODE)"
                    }

                    [Console]::OutputEncoding = $originalOutputEncoding
                    Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
                } elseif ($currentTool -eq 'Codex') {
                    Write-PSFMessage -Level Verbose -Message "Executing Codex in chat mode (prompt in arguments)"

                    # Redirect to temp file instead of capturing directly
                    & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        FileName     = 'N/A (Chat Mode)'
                        FullPath     = 'N/A (Chat Mode)'
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Chat mode completed successfully"
                    } else {
                        Write-PSFMessage -Level Error -Message "Chat mode failed (exit code $LASTEXITCODE)"
                    }
                } elseif ($currentTool -eq 'Cursor') {
                    Write-PSFMessage -Level Verbose -Message "Executing Cursor in chat mode (prompt in arguments)"

                    # Redirect to temp file instead of capturing directly
                    & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        FileName     = 'N/A (Chat Mode)'
                        FullPath     = 'N/A (Chat Mode)'
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Chat mode completed successfully"
                    } else {
                        Write-PSFMessage -Level Error -Message "Chat mode failed (exit code $LASTEXITCODE)"
                    }
                } else {
                    Write-PSFMessage -Level Verbose -Message "Piping prompt to $currentTool in chat mode"

                    # Redirect to temp file instead of capturing directly
                    $fullPrompt | & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    # Filter out misleading Gemini warnings about unreadable directories
                    if ($currentTool -eq 'Gemini') {
                        $capturedOutput = $capturedOutput -replace '(?m)^\s*\[WARN\]\s+Skipping unreadable directory:.*?\n', ''
                    }

                    [PSCustomObject]@{
                        FileName     = 'N/A (Chat Mode)'
                        FullPath     = 'N/A (Chat Mode)'
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Chat mode completed successfully"
                    } else {
                        Write-PSFMessage -Level Error -Message "Chat mode failed (exit code $LASTEXITCODE)"
                    }
                }
            } catch {
                Write-PSFMessage -Level Error -Message "Error in chat mode: $_"
            } finally {
                if ($currentTool -eq 'Codex') {
                    Write-PSFMessage -Level Verbose -Message "Cleaning up RUST_LOG environment variable"
                    Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
                }

                # Restore original location
                if ($script:originalLocation) {
                    Set-Location $script:originalLocation
                    Write-PSFMessage -Level Verbose -Message "Restored location to: $script:originalLocation"
                }
            }

            return
        }

        Write-PSFMessage -Level Verbose -Message "Total files queued: $($filesToProcess.Count)"

        $fileIndex = 0
        $totalFiles = $filesToProcess.Count
        foreach ($singleFile in $filesToProcess) {
            $fileIndex++

            Write-PSFMessage -Level Debug -Message "Processing file $fileIndex of $totalFiles - $singleFile"

            # Show progress for file processing
            $fileName = [System.IO.Path]::GetFileName($singleFile)
            $progressParams = @{
                Activity        = "Processing with $currentTool"
                Status          = "$fileName ($fileIndex/$totalFiles)"
                PercentComplete = ($fileIndex / $totalFiles) * 100
            }
            Write-Progress @progressParams

            # Build combined prompt with context files for non-Aider tools
            $fullPrompt = $promptText
                if ($currentTool -ne 'Aider' -and $contextFiles.Count -gt 0) {
                Write-PSFMessage -Level Verbose -Message "Building combined prompt with $($contextFiles.Count) context file(s)"
                foreach ($ctxFile in $contextFiles) {
                    if (Test-Path $ctxFile) {
                        $content = Get-Content -Path $ctxFile -Raw
                        $fullPrompt += "`n`n--- Context from $($ctxFile) ---`n$content"
                        Write-PSFMessage -Level Verbose -Message "Added context from: $ctxFile"
                    } else {
                        Write-PSFMessage -Level Warning -Message "Context file not found: $ctxFile"
                    }
                }
            }

            # Add ClaudeCode reasoning trigger if needed
            if ($currentTool -eq 'ClaudeCode' -and $reasoningEffortToUse) {
                $reasoningPhrase = switch ($reasoningEffortToUse) {
                    'low'    { 'think hard' }
                    'medium' { 'think harder' }
                    'high'   { 'ultrathink' }
                }
                Write-PSFMessage -Level Verbose -Message "Adding ClaudeCode reasoning trigger: $reasoningPhrase"
                $fullPrompt += "`n`n$reasoningPhrase"
            }

                Write-PSFMessage -Level Verbose -Message "Building arguments for $currentTool"
                $arguments = switch ($currentTool) {
                'ClaudeCode' {
                    $argumentParams = @{
                        TargetFile          = $singleFile
                        Message             = $promptText
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    New-ClaudeArgument @argumentParams
                }
                'Aider' {
                    $argumentParams = @{
                        TargetFile          = $singleFile
                        Message             = $promptText
                        Model               = $modelToUse
                        EditMode            = $editMode
                        ContextFiles        = $contextFiles
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    New-AiderArgument @argumentParams
                }
                'Gemini' {
                    $argumentParams = @{
                        TargetFile          = $singleFile
                        Message             = $promptText
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    New-GeminiArgument @argumentParams
                }
                'GitHubCopilot' {
                    $argumentParams = @{
                        TargetFile          = $singleFile
                        Message             = $promptText
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        WorkingDirectory    = $targetDirectory
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    New-CopilotArgument @argumentParams
                }
                'Codex' {
                    $argumentParams = @{
                        TargetFile          = $singleFile
                        Message             = $promptText
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        WorkingDirectory    = $targetDirectory
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    if ($Attachment) {
                        $argumentParams['Attachment'] = $Attachment
                    }
                    New-CodexArgument @argumentParams
                }
                'Cursor' {
                    $argumentParams = @{
                        TargetFile          = $singleFile
                        Message             = $promptText
                        Model               = $modelToUse
                        ContextFiles        = $contextFiles
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    New-CursorArgument @argumentParams
                }
            }

            Write-PSFMessage -Level Verbose -Message "Executing: $($toolDef.Command) $($arguments -join ' ')"

            Write-PSFMessage -Level Verbose -Message "Big prompt: $fullPrompt"

            # Change to target file's directory to resolve workspace permission issues
            $targetDirectory = Split-Path $singleFile -Parent
            if ($targetDirectory -and (Test-Path $targetDirectory)) {
                Push-Location $targetDirectory
                Write-PSFMessage -Level Verbose -Message "Changed to target directory: $targetDirectory"
            } else {
                Write-PSFMessage -Level Warning -Message "Could not determine target directory for: $singleFile"
            }

            $startTime = Get-Date

            try {
                if ($Raw) {
                    Write-PSFMessage -Level Verbose -Message "Executing in raw mode (no output capturing)"
                    if ($currentTool -eq 'Aider') {
                        $originalOutputEncoding = [Console]::OutputEncoding
                        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                        $env:PYTHONIOENCODING = 'utf-8'

                        & $toolDef.Command @arguments 2>&1 | ForEach-Object {
                            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                                Write-PSFMessage -Level Debug -Message $_.Exception.Message
                            } else {
                                $_
                            }
                        }

                        [Console]::OutputEncoding = $originalOutputEncoding
                        Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
                    } elseif ($currentTool -eq 'Codex') {
                        # Codex receives prompt as command-line argument, no piping needed
                        $originalOutputEncoding = [Console]::OutputEncoding
                        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

                        & $toolDef.Command @arguments 2>&1 | ForEach-Object {
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

                        $fullPrompt | & $toolDef.Command @arguments 2>&1 | ForEach-Object {
                            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                                Write-PSFMessage -Level Debug -Message $_.Exception.Message
                            } else {
                                $_
                            }
                        }

                        [Console]::OutputEncoding = $originalOutputEncoding
                    }

                    # Provide user-friendly feedback based on exit code
                    $exitCode = $LASTEXITCODE
                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $exitCode"

                    if ($exitCode -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "File processed successfully: $singleFile"
                    } else {
                        Write-PSFMessage -Level Warning -Message "Failed to process $singleFile (exit code: $exitCode)"
                        Write-PSFMessage -Level Verbose -Message "Note: Some tools write debug/warning messages to stderr even on success. Check the output above to determine if there was a real error."
                    }

                    continue
                }

                # Create temp file for output redirection (allows tool to run natively while capturing output)
                $tempOutputFile = [System.IO.Path]::GetTempFileName()
                Write-PSFMessage -Level Verbose -Message "Redirecting output to temp file: $tempOutputFile"

                # Output structured object to pipeline with file-based output capture
                if ($currentTool -eq 'Aider') {
                    Write-PSFMessage -Level Verbose -Message "Executing Aider with native --read context files"
                    # Set UTF-8 encoding for aider output to handle Unicode characters
                    $originalOutputEncoding = [Console]::OutputEncoding
                    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                    $env:PYTHONIOENCODING = 'utf-8'

                    # Redirect to temp file instead of capturing directly
                    & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        FileName     = [System.IO.Path]::GetFileName($singleFile)
                        FullPath     = $singleFile
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $singleFile"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $singleFile (exit code $LASTEXITCODE)"
                    }

                    # Restore original encoding
                    [Console]::OutputEncoding = $originalOutputEncoding
                    Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
                } elseif ($currentTool -eq 'Codex') {
                    Write-PSFMessage -Level Verbose -Message "Executing Codex (prompt in arguments)"

                    # Redirect to temp file instead of capturing directly
                    & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        FileName     = [System.IO.Path]::GetFileName($singleFile)
                        FullPath     = $singleFile
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $singleFile"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $singleFile (exit code $LASTEXITCODE)"
                    }
                } elseif ($currentTool -eq 'Cursor') {
                    Write-PSFMessage -Level Verbose -Message "Executing Cursor (prompt in arguments)"

                    # Redirect to temp file instead of capturing directly
                    & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        FileName     = [System.IO.Path]::GetFileName($singleFile)
                        FullPath     = $singleFile
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $singleFile"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $singleFile (exit code $LASTEXITCODE)"
                    }
                } else {
                        Write-PSFMessage -Level Verbose -Message "Piping combined prompt to $currentTool"

                    # Redirect to temp file instead of capturing directly
                    $fullPrompt | & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    # Filter out misleading Gemini warnings about unreadable directories
                    if ($currentTool -eq 'Gemini') {
                        $capturedOutput = $capturedOutput -replace '(?m)^\s*\[WARN\]\s+Skipping unreadable directory:.*?\n', ''
                    }

                    [PSCustomObject]@{
                        FileName     = [System.IO.Path]::GetFileName($singleFile)
                        FullPath     = $singleFile
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($LASTEXITCODE -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $singleFile"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $singleFile (exit code $LASTEXITCODE)"
                    }
                }
            } catch {
                Write-PSFMessage -Level Error -Message "Error processing $singleFile : $_"
            } finally {
                # Clean up Codex environment variable
                if ($currentTool -eq 'Codex') {
                    Write-PSFMessage -Level Verbose -Message "Cleaning up RUST_LOG environment variable"
                    Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
                }

                # Restore location after processing each file
                if ($targetDirectory -and (Test-Path $targetDirectory)) {
                    Pop-Location
                    Write-PSFMessage -Level Verbose -Message "Restored location after processing file"
                }
            }
        } # End of foreach ($singleFile in $filesToProcess)

        Write-Progress -Activity "Processing with $currentTool" -Completed
        } # End of foreach ($currentTool in $toolsToRun)

        Write-PSFMessage -Level Verbose -Message "All files processed"
        Write-PSFMessage -Level Debug -Message "Processing complete."
    }
}
