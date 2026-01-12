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
        If omitted, defaults to "Convert this file according to the instructions."
        The file path will be automatically injected into the prompt if not detected.

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
        Optional image file(s) to attach to the prompt. Currently only used by Codex (via -i flag).
        Accepts common image formats (png, jpg, jpeg, gif, bmp, webp, svg).
        Note: When piping image files with -Tool Codex, they are automatically treated as attachments.
        For other tools, piped images are processed as regular files (tools with vision can analyze them).
        Vision models can see and analyze images but cannot directly edit them - they can write scripts
        or call tools (Python/PIL, ImageMagick, etc.) to manipulate images.

    .PARAMETER Raw
        Run the command directly without capturing output or assigning to variables.
        Useful for interactive scenarios like Jupyter notebooks where output handling can cause issues.

    .PARAMETER DelaySeconds
        Number of seconds to wait after processing each file. Useful for rate limiting or spreading
        API calls over time to manage credit usage (e.g., -DelaySeconds 10 for a 10-second delay).

    .PARAMETER DisableRetry
        Disable automatic retry with exponential backoff. By default, transient errors (timeouts,
        rate limits, server errors, connection issues, quota/usage limits) are retried with delays
        of 2, 4, 8, 16, 32, 64 minutes until the cumulative delay exceeds MaxRetryMinutes.
        Non-retryable errors (e.g., invalid arguments, file not found) fail immediately.
        Use this switch to disable retry and fail immediately on all errors.

    .PARAMETER MaxRetryMinutes
        Maximum total time in minutes for all retry delays combined. Default is 240 (4 hours).
        Only applies when retry is enabled (default behavior).

    .PARAMETER SkipModified
        Skip files that have been modified in the working tree or differ from the upstream branch.
        Useful for resuming batch operations after hitting rate limits - prevents reprocessing files
        that were already changed by the AI tool. Includes:
        - Uncommitted working tree changes (modified files not yet staged)
        - Staged changes (files added to the index)
        - Committed but not pushed changes (commits unique to this branch)
        Only works in git repositories with an upstream branch configured.
        When on the main/upstream branch, uses -CommitDepth to check recent commit history instead.

    .PARAMETER CommitDepth
        When -SkipModified is used on the main/upstream branch, specifies how many recent commits
        to check for file modifications. Defaults to 5. This prevents reprocessing files that were
        recently modified in the main branch history. Only used when on main/master/trunk branches.

    .PARAMETER NoParallel
        Disables parallel processing and processes files/batches sequentially. By default, when processing
        4 or more files (or batches when using -BatchSize), they are processed in parallel with up to 3
        concurrent threads. Use this switch to force sequential processing regardless of file/batch count.

    .PARAMETER MaxThreads
        Maximum number of concurrent threads for parallel processing. Default is 3 to avoid API
        rate limiting. Can be increased for better performance, but higher values may trigger
        API throttling depending on your service provider's quotas and limits.
        When used with -BatchSize, this controls how many batches run concurrently (not individual files).

    .PARAMETER Skip
        Skips the specified number of files from the beginning of the pipeline input.
        Works like Select-Object -Skip. Can be combined with -First and -Last.

    .PARAMETER First
        Processes only the first N files from the pipeline input (after applying -Skip if specified).
        Works like Select-Object -First. Can be combined with -Last to get both first and last items.

    .PARAMETER Last
        Processes only the last N files from the pipeline input (after applying -Skip if specified).
        Works like Select-Object -Last. Can be combined with -First to get both first and last items.

    .PARAMETER BatchSize
        Number of files to process together in a single AI request. Default is 1 (one file at a time).
        When set to a value greater than 1, multiple files are combined into a single prompt to reduce
        token usage and API calls. Useful for batch translation, formatting, or other similar operations.
        Note: The AI's response must include clear file separators or filenames to distinguish outputs.
        Batches can be processed in parallel when there are 4+ batches - use -MaxThreads to control
        concurrency (e.g., 12 files with -BatchSize 3 creates 4 batches that can run 3 at a time).

        Recommendation: A BatchSize of 3 has shown good results for most workloads. If you experience
        inconsistencies or quality issues in AI responses when trying for higher numbers like 5 or 10, reduce this to see what works best for your workload.

    .PARAMETER ContextFilter
        A scriptblock that transforms each input filename to derive a matching context file.
        This enables pairing files (like translations) with their originals without sending all
        originals to every batch. The scriptblock receives each input file path via $_ and should
        return the filename (or path) of the corresponding context file.

        Example: -ContextFilter { $_ -replace '\.fr\.md$', '.md' }
        This transforms 'recipe1.fr.md' to 'recipe1.md', allowing French translations to include
        their English originals as context.

        Path resolution order:
        1. If result is an absolute path and exists, use it directly
        2. If result is relative: look in -ContextFilterBase directory (if specified),
           otherwise look in the same directory as the source file
        3. If file not found, warn and continue (doesn't fail the batch)

        Edge cases handled:
        - Returns same file as input: skipped (won't add file as its own context)
        - Returns non-existent file: warns, continues processing
        - Throws error: catches, warns, continues with other files
        - Duplicate derived files in batch: deduplicated (same context added only once)

    .PARAMETER ContextFilterBase
        Base directory or directories to search for files derived by -ContextFilter. Accepts
        an array of paths that are searched in order until the derived file is found. The source
        file's directory is always searched last as a fallback.

        Example: -ContextFilterBase "C:\originals"
        Combined with -ContextFilter { [System.IO.Path]::GetFileName($_) -replace '\.fr\.md$', '.md' }
        would look for English originals in C:\originals, then fall back to the source file's directory.

        Example with multiple directories: -ContextFilterBase "C:\primary", "C:\fallback"
        Searches C:\primary first, then C:\fallback, then the source file's directory.

    .PARAMETER MaxErrors
        Maximum number of general errors before bailing out of batch processing. Default is 10.
        When this threshold is reached, remaining files/batches are skipped to avoid wasting
        API calls on a failing operation. Useful when processing many files in parallel.

    .PARAMETER MaxTokenErrors
        Maximum number of token/credit-related errors before bailing out. Default is 3.
        Token errors are detected by patterns like "token", "credits", "exhausted", "quota",
        "insufficient", "billing", "payment". A lower threshold is used because these errors
        typically indicate account-wide issues that won't resolve by retrying other files.

    .PARAMETER IgnoreInstructions
        When enabled, the AI tool will ignore instruction files like CLAUDE.md, AGENTS.md, and other
        custom instruction files that are normally auto-loaded. This is useful when you want to run
        the tool without project-specific or user-specific instructions.

        For Claude: Uses an empty --system-prompt to bypass CLAUDE.md loading
        For Copilot: Uses --no-custom-instructions to bypass AGENTS.md loading
        For other tools: Behavior varies based on tool capabilities

        This parameter overrides the configured default from Set-AIToolConfig.

    .EXAMPLE
        Get-ChildItem *.Tests.ps1 | Invoke-AITool -Prompt "Refactor from Pester v4 to v5"

    .EXAMPLE
        Get-ChildItem *.md | Invoke-AITool -Context "prompts\wordpress-to-hugo.md"
        Uses the default prompt with instructions from the context file. File paths are auto-injected.

    .EXAMPLE
        Invoke-AITool -Path "MyFile.ps1" -Prompt "Add help documentation" -Tool Claude -Verbose

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Fix style" -Context "StyleGuide.md" -Tool Aider -Debug

    .EXAMPLE
        Invoke-AITool -Path "MyFile.ps1" -Prompt (Get-ChildItem prompts\style.md) -Tool Aider

    .EXAMPLE
        $contextFiles = Get-ChildItem *.md
        Invoke-AITool -Path "test.ps1" -Prompt "Fix code" -Context $contextFiles -Tool Aider

    .EXAMPLE
        Invoke-AITool -Prompt "How do I implement error handling in PowerShell?" -Tool Claude

    .EXAMPLE
        Invoke-AITool -Path "complex.ps1" -Prompt "Optimize this code" -Tool Codex -ReasoningEffort high

    .EXAMPLE
        Invoke-AITool -Path "script.ps1" -Prompt "Add error handling" -Tool All
        Runs the same prompt against all installed tools sequentially.

    .EXAMPLE
        Invoke-AITool -Path "MyFile.ps1" -Prompt "Refactor code"
        Processes the file with automatic retry on transient errors (timeouts, rate limits, server errors)
        using exponential backoff (2, 4, 8, 16, 32, 64 mins) for up to 4 hours total (default behavior).

    .EXAMPLE
        Invoke-AITool -Path "MyFile.ps1" -Prompt "Refactor code" -DisableRetry
        Processes the file without retry - fails immediately on error.

    .EXAMPLE
        Invoke-AITool -Path "MyFile.ps1" -Prompt "Refactor code" -MaxRetryMinutes 60
        Processes the file with retry enabled but only retry for up to 1 hour total delay time.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Add error handling" -SkipModified
        Processes only files that haven't been modified, skipping files with uncommitted changes,
        staged changes, or committed but not pushed changes.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Add error handling" -SkipModified -CommitDepth 10
        When on main branch, checks the last 10 commits for modified files to skip. When on a feature
        branch, uses the standard behavior of checking uncommitted/unpushed changes.

    .EXAMPLE
        Get-ChildItem diagram.png | Invoke-AITool -Prompt "Describe what's in this image" -Tool Codex
        Pipes an image file which is automatically detected and treated as an attachment for Codex (using -i flag).

    .EXAMPLE
        Get-ChildItem photo.jpg | Invoke-AITool -Prompt "Describe this image" -Tool Claude
        Pipes an image file to Claude as a regular file. Claude can analyze and describe the image.

    .EXAMPLE
        Get-ChildItem photo.jpg | Invoke-AITool -Prompt "Write a Python script using PIL to add a 10px white border" -Tool Codex
        Codex can see the image and write/execute scripts to manipulate it using tools like PIL, ImageMagick, etc.

    .EXAMPLE
        Invoke-AITool -Attachment "screenshot.png" -Prompt "What UI framework was used?" -Tool Codex
        Explicitly attaches an image file for Codex to analyze using the -i flag.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Add error handling"
        Processes files in parallel (default behavior for 4+ files) with up to 3 concurrent operations.
        Results are streamed as they complete.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Add error handling" -NoParallel
        Processes files sequentially one at a time, even if there are many files.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Add error handling" -MaxThreads 5
        Processes files in parallel with up to 5 concurrent operations. WARNING: Higher thread counts
        may trigger API rate limits depending on your AI service provider's quotas.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Fix bugs" -First 5
        Processes only the first 5 PowerShell files from the pipeline.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Fix bugs" -Skip 2 -First 3
        Skips the first 2 files, then processes the next 3 files (files 3, 4, and 5).

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Fix bugs" -Last 3
        Processes only the last 3 PowerShell files from the pipeline.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Fix bugs" -First 2 -Last 2
        Processes the first 2 and last 2 files from the pipeline (like Select-Object behavior).

    .EXAMPLE
        Get-ChildItem *.md | Invoke-AITool -Context "glossary.md" -Prompt "prompt.md" -BatchSize 3
        Processes 3 markdown files at a time in a single AI request to reduce token usage.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Add error handling" -BatchSize 3 -MaxThreads 3
        With 12+ files: Creates batches of 3 files each, then processes 3 batches concurrently.
        This combines token savings (batching) with speed (parallelism).

    .EXAMPLE
        Get-ChildItem *.fr.md | Invoke-AITool -Prompt "Review translation" -ContextFilter { $_ -replace '\.fr\.md$', '.md' }
        For each French markdown file, automatically includes the corresponding English original as context.
        recipe1.fr.md gets recipe1.md as context, recipe2.fr.md gets recipe2.md, etc.

    .EXAMPLE
        Get-ChildItem *.fr.md | Invoke-AITool -Prompt "Review translation" -Context "glossary.md" -ContextFilter { $_ -replace '\.fr\.md$', '.md' } -BatchSize 4
        Combines static context (glossary.md added to every batch) with dynamic context (each French file
        gets its English original). With BatchSize 4, each batch gets the glossary plus up to 4 original files.

    .EXAMPLE
        Get-ChildItem C:\translations\*.fr.md | Invoke-AITool -Prompt "Check consistency" -ContextFilter { [System.IO.Path]::GetFileName($_) -replace '\.fr\.md$', '.md' } -ContextFilterBase "C:\originals"
        Processes French files from C:\translations but looks for English originals in C:\originals.

    .EXAMPLE
        Get-ChildItem *.fr.md | Invoke-AITool -Prompt "Review" -ContextFilter { $_ -replace '\.fr\.md$', '.md' } -WhatIf
        Preview which dynamic context files would be added without actually processing.

    .EXAMPLE
        Invoke-AITool -Path "script.ps1" -Prompt "Review this code" -IgnoreInstructions
        Processes the file without loading CLAUDE.md, AGENTS.md, or other instruction files.

    .EXAMPLE
        Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Fix bugs" -Tool Claude -IgnoreInstructions
        Processes all PowerShell files with Claude, bypassing any project or user instructions.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [Alias('Name')]
        [string]$Tool,
        [object]$Prompt,
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'File', 'FilePath')]
        [string[]]$Path,
        [Parameter()]
        [Alias('Instructions')]
        [object[]]$Context,
        [Parameter()]
        [string]$Model,
        [Parameter()]
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort,
        [Parameter()]
        [string[]]$Attachment,
        [Parameter()]
        [switch]$Raw,
        [Parameter()]
        [ValidateRange(0, 3600)]
        [int]$DelaySeconds = 0,
        [Parameter()]
        [switch]$DisableRetry,
        [Parameter()]
        [ValidateRange(1, 1440)]  # 1 minute to 24 hours
        [int]$MaxRetryMinutes = 240,
        [Parameter()]
        [switch]$SkipModified,
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$CommitDepth = 10,
        [Parameter()]
        [switch]$NoParallel,
        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$MaxThreads = 3,
        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Skip,
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$First,
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last,
        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$BatchSize = 1,
        [Parameter()]
        [scriptblock]$ContextFilter,
        [Parameter()]
        [string[]]$ContextFilterBase,
        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$MaxErrors = 10,
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxTokenErrors = 3,
        [Parameter()]
        [switch]$IgnoreInstructions
    )

    begin {
        # Save original location for cleanup in finally block
        $script:originalLocation = Get-Location
        Write-PSFMessage -Level Verbose -Message "Saved original location: $script:originalLocation"

        # BatchSize > 1 automatically disables parallel processing
        if ($BatchSize -gt 1) {
            Write-PSFMessage -Level Verbose -Message "BatchSize set to $BatchSize - parallel processing will be automatically disabled for batch mode"
        }

        # Initialize attachment array if not already set (for piped images)
        $imageAttachments = @()
        if ($Attachment) {
            $imageAttachments = @($Attachment)
        }

        # Setup git context and initial snapshot if -SkipModified is specified
        $gitContext = $null
        $initialModifiedSnapshot = @{}
        $script:cachedRepoRoot = $null

        if ($SkipModified) {
            $gitContext = Initialize-GitContext -CommitDepth $CommitDepth
            if ($gitContext) {
                $script:cachedRepoRoot = $gitContext.RepoRoot
                $initialModifiedSnapshot = Get-InitialModifiedSnapshot -GitContext $gitContext
            } else {
                Write-PSFMessage -Level Warning -Message "-SkipModified specified but git context could not be initialized. Parameter will be ignored."
            }
        }

        # Set default prompt if none provided
        if (-not $Prompt) {
            $Prompt = "Convert this file according to the instructions."
            Write-PSFMessage -Level Verbose -Message "No prompt provided, using default: $Prompt"
        }

        # Process Prompt parameter using helper function
        $promptResult = ConvertTo-PromptText -Prompt $Prompt
        $promptText = $promptResult.Text
        $promptFilePath = $promptResult.FilePath

        # Process Context parameter using helper function
        $contextFiles = Resolve-ContextFiles -Context $Context

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

        # Resolve tool alias to canonical name
        $Tool = Resolve-ToolAlias -ToolName $Tool

        Write-PSFMessage -Level Verbose -Message "Starting Invoke-AITool with tool: $Tool"

        # Handle "All" tool selection - get all available tools
        $toolsToRun = @()
        if ($Tool -eq 'All' -or $Tool -eq '*') {
            Write-PSFMessage -Level Verbose -Message "Tool is '$Tool' - will run all available tools"
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
        $script:totalInputFiles = 0

        # Error tracking for bail-out feature
        $script:errorCount = 0
        $script:tokenErrorCount = 0
        $script:bailedOut = $false
    }

    process {
        foreach ($file in $Path) {
            $script:totalInputFiles++
            $resolvedPath = Resolve-Path -Path $file -ErrorAction SilentlyContinue
            if ($resolvedPath) {
                # Normalize path to use forward slashes for cross-platform CLI compatibility
                $normalizedPath = $resolvedPath.Path -replace '\\', '/'

                # Stage 1: Quick check against initial snapshot if -SkipModified is specified
                if ($SkipModified -and $gitContext) {
                    if ($initialModifiedSnapshot.ContainsKey($normalizedPath)) {
                        Write-PSFMessage -Level Verbose -Message "Skipping file (initial sweep): $normalizedPath"
                        continue
                    }
                }

                # Check if this is an image file - route to attachments for Codex, regular files for others
                $extension = [System.IO.Path]::GetExtension($normalizedPath).ToLower()
                $validImageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg')

                # Determine the effective tool (considering default and aliases)
                $effectiveTool = if ($Tool) {
                    Resolve-ToolAlias -ToolName $Tool
                } else {
                    $defaultTool = Get-PSFConfigValue -FullName 'AITools.DefaultTool' -Fallback $null
                    if ($defaultTool) { Resolve-ToolAlias -ToolName $defaultTool } else { $null }
                }

                if ($extension -in $validImageExtensions -and $effectiveTool -eq 'Codex') {
                    Write-PSFMessage -Level Verbose -Message "Detected image file for Codex, adding as attachment: $normalizedPath"
                    $imageAttachments += $normalizedPath
                } else {
                    $filesToProcess += $normalizedPath
                    Write-PSFMessage -Level Debug -Message "Queued file: $normalizedPath"
                }
            } else {
                Write-PSFMessage -Level Warning -Message "File not found: $file"
            }
        }
    }

    end {
        # Validate attachments (including those collected from pipeline)
        if ($imageAttachments.Count -gt 0) {
            $validImageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg')
            foreach ($attachmentPath in $imageAttachments) {
                $extension = [System.IO.Path]::GetExtension($attachmentPath).ToLower()
                if ($extension -notin $validImageExtensions) {
                    Stop-PSFFunction -Message "Invalid attachment file type: $attachmentPath. Only image files are supported: $($validImageExtensions -join ', ')" -EnableException $true
                    return
                }

                if (-not (Test-Path $attachmentPath)) {
                    Stop-PSFFunction -Message "Attachment file not found: $attachmentPath" -EnableException $true
                    return
                }
            }

            Write-PSFMessage -Level Verbose -Message "Validated $($imageAttachments.Count) attachment(s): $($imageAttachments -join ', ')"
        }

        # Apply -Skip, -First, and -Last filtering using Select-Object
        if ($filesToProcess.Count -gt 0 -and (Test-PSFParameterBinding -ParameterName 'Skip', 'First', 'Last')) {
            $originalCount = $filesToProcess.Count

            $selectParams = @{}
            if (Test-PSFParameterBinding -ParameterName 'Skip') { $selectParams['Skip'] = $Skip }
            if (Test-PSFParameterBinding -ParameterName 'First') { $selectParams['First'] = $First }
            if (Test-PSFParameterBinding -ParameterName 'Last') { $selectParams['Last'] = $Last }

            $filesToProcess = @($filesToProcess | Select-Object @selectParams)

            Write-PSFMessage -Level Verbose -Message "File filtering applied: $originalCount → $($filesToProcess.Count) file(s) (Skip:$Skip First:$First Last:$Last)"
        }

        # Early check: If no files to process and user expects file processing (not chat mode), exit early
        if ($filesToProcess.Count -eq 0 -and $script:totalInputFiles -gt 0) {
            Write-PSFMessage -Level Warning -Message "All $script:totalInputFiles file(s) were skipped (likely due to -SkipModified filtering). No files to process."
            Write-Information "All $script:totalInputFiles file(s) were skipped. Nothing to process." -InformationAction Continue
            return
        }

        # Loop through each tool (will be one tool or multiple if "All" was selected)
        foreach ($currentTool in $toolsToRun) {
            Write-PSFMessage -Level Verbose -Message "Processing with tool: $currentTool"

            # Get tool definition and validate installation
            $toolDef = $script:ToolDefinitions[$currentTool]
            if (-not (Test-Command -Command $toolDef.Command)) {
                Write-PSFMessage -Level Warning -Message "$currentTool is not installed. Skipping. Run: Install-AITool -Name $currentTool"
                continue
            }

            # Check Gemini authentication
            if ($currentTool -eq 'Gemini' -and -not (Test-GeminiAuth)) {
                Write-PSFMessage -Level Warning -Message "Gemini authentication not configured. Please set an auth method in ~/.gemini/settings.json or specify one of the following environment variables: GEMINI_API_KEY, GOOGLE_GENAI_USE_VERTEXAI, GOOGLE_GENAI_USE_GCA. Skipping."
                continue
            }

            # Load configuration for current tool using helper function
            $configParams = @{
                ToolName                    = $currentTool
                ModelOverride               = $Model
                ReasoningEffortOverride     = $ReasoningEffort
                IgnoreInstructionsOverride  = $IgnoreInstructions
                IgnoreInstructionsBound     = $PSBoundParameters.ContainsKey('IgnoreInstructions')
            }
            $toolConfig = Get-ToolConfiguration @configParams

            $permissionBypass = $toolConfig.PermissionBypass
            $modelToUse = $toolConfig.Model
            $editMode = $toolConfig.EditMode
            $reasoningEffortToUse = $toolConfig.ReasoningEffort
            $ignoreInstructionsToUse = $toolConfig.IgnoreInstructions

            # Chat mode (no files specified)
            if ($filesToProcess.Count -eq 0) {
                $chatParams = @{
                    ToolName           = $currentTool
                    ToolDefinition     = $toolDef
                    PromptText         = $promptText
                    ContextFiles       = $contextFiles
                    Model              = $modelToUse
                    ReasoningEffort    = $reasoningEffortToUse
                    PermissionBypass   = $permissionBypass
                    IgnoreInstructions = $ignoreInstructionsToUse
                    EditMode           = $editMode
                    ImageAttachments   = $imageAttachments
                    PromptFilePath     = $promptFilePath
                    Raw                = $Raw
                    DisableRetry       = $DisableRetry
                    MaxRetryMinutes    = $MaxRetryMinutes
                    OriginalLocation   = $script:originalLocation
                }
                $chatResult = Invoke-ChatMode @chatParams

                if ($chatResult) {
                    $chatResult
                }
                return
            }

            Write-PSFMessage -Level Verbose -Message "Total files queued: $($filesToProcess.Count)"

            # Warn if MaxThreads is higher than default
            if ($MaxThreads -gt 3) {
                Write-PSFMessage -Level Warning -Message "Using $MaxThreads concurrent threads. This may trigger API rate limits depending on your service provider's quotas."
                Write-Warning "Using $MaxThreads threads may cause API rate limiting. Consider reducing -MaxThreads if you encounter throttling errors."
            }

            # Group files into batches based on BatchSize parameter
            $batches = @()
            for ($i = 0; $i -lt $filesToProcess.Count; $i += $BatchSize) {
                $batchEnd = [Math]::Min($i + $BatchSize, $filesToProcess.Count)
                $batches += ,@($filesToProcess[$i..($batchEnd - 1)])
            }

            # Determine if parallel processing should be used (based on batch count, not file count)
            $shouldUseParallel = (-not $NoParallel) -and ($batches.Count -ge 4)

            try {
                if ($shouldUseParallel) {
                    # Parallel execution using helper function
                    if ($BatchSize -gt 1) {
                        Write-PSFMessage -Level Verbose -Message "Parallel batch mode enabled: $($filesToProcess.Count) files in $($batches.Count) batches - max $MaxThreads threads"
                    } else {
                        Write-PSFMessage -Level Verbose -Message "Parallel mode enabled for $($filesToProcess.Count) files - max $MaxThreads threads"
                    }

                    $parallelParams = @{
                        Batches           = $batches
                        ToolName          = $currentTool
                        PromptText        = $promptText
                        MaxThreads        = $MaxThreads
                        ContextFiles      = $contextFiles
                        Model             = $modelToUse
                        ReasoningEffort   = $reasoningEffortToUse
                        DisableRetry      = $DisableRetry
                        MaxRetryMinutes   = $MaxRetryMinutes
                        SkipModified      = $SkipModified
                        BatchSize         = $BatchSize
                        ContextFilter     = $ContextFilter
                        ContextFilterBase = $ContextFilterBase
                        MaxErrors         = $MaxErrors
                        MaxTokenErrors    = $MaxTokenErrors
                        ModuleRoot        = $script:ModuleRoot
                        ErrorCountRef     = [ref]$script:errorCount
                        TokenErrorCountRef = [ref]$script:tokenErrorCount
                        BailedOutRef      = [ref]$script:bailedOut
                    }
                    Start-ParallelExecution @parallelParams

                } else {
                    # Sequential processing
                    if ($NoParallel) {
                        Write-PSFMessage -Level Verbose -Message "Sequential processing enforced by -NoParallel switch"
                    } elseif ($BatchSize -gt 1) {
                        Write-PSFMessage -Level Verbose -Message "Sequential batch processing: $($filesToProcess.Count) files in $($batches.Count) batch(es)"
                    } else {
                        Write-PSFMessage -Level Verbose -Message "Sequential processing (only $($filesToProcess.Count) file(s), parallel is used for 4+ files)"
                    }

                    $fileIndex = 0
                    $totalFiles = $filesToProcess.Count
                    $batchIndex = 0

                    foreach ($batch in $batches) {
                        # Check for bail-out before processing each batch
                        if ($script:bailedOut) {
                            Write-PSFMessage -Level Warning -Message "Skipping remaining batches due to bail-out"
                            break
                        }
                        $batchIndex++

                        # Filter out modified files from this batch if -SkipModified is enabled
                        $batchFilesToProcess = @()
                        foreach ($singleFile in $batch) {
                            $fileIndex++

                            # Stage 2: Fresh verification right before execution
                            if ($SkipModified -and $gitContext -and $script:cachedRepoRoot) {
                                if (Test-FileModifiedFresh -FilePath $singleFile -RepoRoot $script:cachedRepoRoot) {
                                    Write-PSFMessage -Level Verbose -Message "Skipping file (fresh check): $singleFile"
                                    continue
                                }
                            }

                            $batchFilesToProcess += $singleFile
                        }

                        # Skip this batch if all files were filtered out
                        if ($batchFilesToProcess.Count -eq 0) {
                            Write-PSFMessage -Level Verbose -Message "Batch $batchIndex skipped - all files were filtered"
                            continue
                        }

                        Write-PSFMessage -Level Debug -Message "Processing batch $batchIndex of $($batches.Count) with $($batchFilesToProcess.Count) file(s)"

                        # Show progress
                        $batchFileNames = ($batchFilesToProcess | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
                        $progressParams = @{
                            Activity        = "Processing with $currentTool"
                            Status          = "Batch $batchIndex/$($batches.Count): $batchFileNames"
                            PercentComplete = (($batchIndex - 1) / $batches.Count) * 100
                        }
                        Write-Progress @progressParams

                        # Build prompt using appropriate helper function
                        if ($BatchSize -gt 1) {
                            $batchPromptParams = @{
                                BasePrompt         = $promptText
                                FilesToProcess     = $batchFilesToProcess
                                StaticContextFiles = $contextFiles
                                ContextFilter      = $ContextFilter
                                ContextFilterBase  = $ContextFilterBase
                                ToolName           = $currentTool
                                ReasoningEffort    = $reasoningEffortToUse
                                PSCmdlet           = $PSCmdlet
                            }
                            $promptBuild = Build-BatchPrompt @batchPromptParams
                        } else {
                            $singlePromptParams = @{
                                BasePrompt         = $promptText
                                FilePath           = $batchFilesToProcess[0]
                                StaticContextFiles = $contextFiles
                                ContextFilter      = $ContextFilter
                                ContextFilterBase  = $ContextFilterBase
                                ToolName           = $currentTool
                                ReasoningEffort    = $reasoningEffortToUse
                                PromptFilePath     = $promptFilePath
                                PSCmdlet           = $PSCmdlet
                            }
                            $promptBuild = Build-SingleFilePrompt @singlePromptParams
                        }

                        $fullPrompt = $promptBuild.FullPrompt
                        $targetFile = $promptBuild.TargetFile
                        $targetDirectory = $promptBuild.TargetDirectory

                        # Change to target file's directory
                        if ($targetDirectory -and (Test-Path $targetDirectory)) {
                            Push-Location $targetDirectory
                            Write-PSFMessage -Level Verbose -Message "Changed to target directory: $targetDirectory"
                        }

                        # Build tool-specific arguments
                        Write-PSFMessage -Level Verbose -Message "Building arguments for $currentTool"
                        $arguments = switch ($currentTool) {
                            'Claude' {
                                $argumentParams = @{
                                    TargetFile          = $targetFile
                                    Message             = $promptText
                                    Model               = $modelToUse
                                    UsePermissionBypass = $permissionBypass
                                    IgnoreInstructions  = $ignoreInstructionsToUse
                                }
                                if ($reasoningEffortToUse) {
                                    $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                                }
                                New-ClaudeArgument @argumentParams
                            }
                            'Aider' {
                                $argumentParams = @{
                                    TargetFile          = $targetFile
                                    Message             = $promptText
                                    Model               = $modelToUse
                                    EditMode            = $editMode
                                    ContextFiles        = $contextFiles
                                    UsePermissionBypass = $permissionBypass
                                }
                                if ($reasoningEffortToUse) {
                                    $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                                }
                                New-AiderArgument @argumentParams
                            }
                            'Gemini' {
                                $argumentParams = @{
                                    TargetFile          = $targetFile
                                    Message             = $promptText
                                    Model               = $modelToUse
                                    UsePermissionBypass = $permissionBypass
                                }
                                New-GeminiArgument @argumentParams
                            }
                            'Copilot' {
                                $argumentParams = @{
                                    TargetFile          = $targetFile
                                    Message             = $promptText
                                    Model               = $modelToUse
                                    UsePermissionBypass = $permissionBypass
                                    IgnoreInstructions  = $ignoreInstructionsToUse
                                    WorkingDirectory    = $targetDirectory
                                    PromptFilePath      = $promptFilePath
                                    ContextFilePaths    = $contextFiles
                                }
                                New-CopilotArgument @argumentParams
                            }
                            'Codex' {
                                $argumentParams = @{
                                    TargetFile          = $targetFile
                                    Message             = $promptText
                                    Model               = $modelToUse
                                    UsePermissionBypass = $permissionBypass
                                    WorkingDirectory    = $targetDirectory
                                }
                                if ($reasoningEffortToUse) {
                                    $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                                }
                                if ($imageAttachments.Count -gt 0) {
                                    $argumentParams['Attachment'] = $imageAttachments
                                }
                                New-CodexArgument @argumentParams
                            }
                            'Cursor' {
                                $argumentParams = @{
                                    TargetFile          = $targetFile
                                    Message             = $promptText
                                    Model               = $modelToUse
                                    ContextFiles        = $contextFiles
                                    UsePermissionBypass = $permissionBypass
                                }
                                if ($reasoningEffortToUse) {
                                    $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                                }
                                New-CursorArgument @argumentParams
                            }
                            'Ollama' {
                                $argumentParams = @{
                                    TargetFile          = $targetFile
                                    Message             = $promptText
                                    Model               = $modelToUse
                                    UsePermissionBypass = $permissionBypass
                                }
                                New-OllamaArgument @argumentParams
                            }
                            'PSOpenAI' {
                                $null
                            }
                        }

                        # Special handling for PSOpenAI (PowerShell module wrapper, not a CLI)
                        if ($currentTool -eq 'PSOpenAI') {
                            Write-PSFMessage -Level Verbose -Message "Invoking PSOpenAI module for image editing"
                            try {
                                $psopenaiParams = @{
                                    Prompt         = $promptText
                                    InputImage     = $targetFile
                                    GenerationType = 'Image'
                                }
                                if ($modelToUse) {
                                    $psopenaiParams['Model'] = $modelToUse
                                }

                                $result = Invoke-PSOpenAI @psopenaiParams
                                $result
                                continue
                            } catch {
                                Write-PSFMessage -Level Error -Message "PSOpenAI invocation failed: $_"
                                continue
                            }
                        }

                        Write-PSFMessage -Level Debug -Message "Final prompt sent to $currentTool :`n$fullPrompt"

                        $startTime = Get-Date
                        $capturedOutput = $null
                        $toolExitCode = 0

                        try {
                            if ($Raw) {
                                Write-PSFMessage -Level Verbose -Message "Executing in raw mode (no output capturing)"
                                $rawOutput = $null
                                if ($currentTool -eq 'Aider') {
                                    $originalOutputEncoding = [Console]::OutputEncoding
                                    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                                    $env:PYTHONIOENCODING = 'utf-8'
                                    $env:LITELLM_NUM_RETRIES = '0'

                                    $rawOutput = & $toolDef.Command @arguments 2>&1 | ForEach-Object {
                                        if ($_ -is [System.Management.Automation.ErrorRecord]) {
                                            Write-PSFMessage -Level Debug -Message $_.Exception.Message
                                        } else {
                                            $_
                                        }
                                    }

                                    [Console]::OutputEncoding = $originalOutputEncoding
                                    Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
                                } elseif ($currentTool -eq 'Codex') {
                                    $originalOutputEncoding = [Console]::OutputEncoding
                                    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

                                    $rawOutput = & $toolDef.Command @arguments 2>&1 | ForEach-Object {
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

                                    $rawOutput = $fullPrompt | & $toolDef.Command @arguments 2>&1 | ForEach-Object {
                                        if ($_ -is [System.Management.Automation.ErrorRecord]) {
                                            Write-PSFMessage -Level Debug -Message $_.Exception.Message
                                        } else {
                                            $_
                                        }
                                    }

                                    [Console]::OutputEncoding = $originalOutputEncoding
                                }

                                # Strip to JSON boundaries if single JSON context mode
                                if ($script:singleJson -and $rawOutput) {
                                    $rawString = if ($rawOutput -is [array]) { $rawOutput | Out-String } else { $rawOutput }
                                    $firstBrace = $rawString.IndexOf('{')
                                    $lastBrace = $rawString.LastIndexOf('}')
                                    if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
                                        $rawOutput = $rawString.Substring($firstBrace, $lastBrace - $firstBrace + 1)
                                        Write-PSFMessage -Level Verbose -Message "Stripped raw output to JSON boundaries for single JSON context mode"
                                    }
                                }

                                # Output the result
                                $rawOutput

                                $exitCode = $LASTEXITCODE
                                Write-PSFMessage -Level Verbose -Message "Tool exited with code: $exitCode"

                                if ($exitCode -eq 0) {
                                    Write-PSFMessage -Level Verbose -Message "Batch processed successfully"
                                } else {
                                    Write-PSFMessage -Level Warning -Message "Failed to process batch (exit code: $exitCode)"
                                }

                                continue
                            }

                            # Create temp file for output redirection
                            $tempOutputFile = [System.IO.Path]::GetTempFileName()
                            Write-PSFMessage -Level Verbose -Message "Redirecting output to temp file: $tempOutputFile"

                            $batchDesc = if ($BatchSize -gt 1) { "batch of $($batchFilesToProcess.Count) file(s)" } else { $targetFile }

                            if ($currentTool -eq 'Aider') {
                                Write-PSFMessage -Level Verbose -Message "Executing Aider with native --read context files"
                                $originalOutputEncoding = [Console]::OutputEncoding
                                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                                $env:PYTHONIOENCODING = 'utf-8'
                                $env:LITELLM_NUM_RETRIES = '0'

                                $executionScriptBlock = {
                                    $outFileParams = @{
                                        FilePath = $tempOutputFile
                                        Encoding = 'utf8'
                                    }
                                    & $toolDef.Command @arguments *>&1 | Tee-Object @outFileParams
                                }.GetNewClosure()

                                $capturedOutput = Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Aider processing $batchDesc"
                                $toolExitCode = $LASTEXITCODE

                                Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                                if ($capturedOutput -is [array]) {
                                    $capturedOutput = $capturedOutput | Out-String
                                }

                                [Console]::OutputEncoding = $originalOutputEncoding
                                Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue

                            } elseif ($currentTool -eq 'Codex') {
                                Write-PSFMessage -Level Verbose -Message "Executing Codex (prompt in arguments)"

                                $executionScriptBlock = [ScriptBlock]::Create(@"
& '$($toolDef.Command)' $($arguments | ForEach-Object { if ($_ -match '\s') { "'$($_.Replace("'", "''"))'" } else { $_ } }) *>&1 | Out-File -FilePath '$tempOutputFile' -Encoding utf8
"@)

                                Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Codex processing $batchDesc"
                                $toolExitCode = $LASTEXITCODE

                                $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                                Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                            } elseif ($currentTool -eq 'Cursor') {
                                Write-PSFMessage -Level Verbose -Message "Executing Cursor (prompt in arguments)"

                                $executionScriptBlock = {
                                    & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
                                }.GetNewClosure()

                                Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Cursor processing $batchDesc"
                                $toolExitCode = $LASTEXITCODE

                                $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                                Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                            } else {
                                Write-PSFMessage -Level Verbose -Message "Piping combined prompt to $currentTool"

                                $executionScriptBlock = {
                                    $fullPrompt | & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
                                }.GetNewClosure()

                                Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$currentTool processing $batchDesc"
                                $toolExitCode = $LASTEXITCODE

                                $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                                Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                                # Filter out misleading Gemini warnings
                                if ($currentTool -eq 'Gemini') {
                                    $capturedOutput = $capturedOutput -replace '(?m)^\s*\[WARN\]\s+Skipping unreadable directory:.*?\n', ''
                                }

                                # Strip result to JSON boundaries if single JSON context mode
                                if ($script:singleJson -and $capturedOutput) {
                                    $firstBrace = $capturedOutput.IndexOf('{')
                                    $lastBrace = $capturedOutput.LastIndexOf('}')
                                    if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
                                        $capturedOutput = $capturedOutput.Substring($firstBrace, $lastBrace - $firstBrace + 1)
                                        Write-PSFMessage -Level Verbose -Message "Stripped result to JSON boundaries for single JSON context mode"
                                    }
                                }
                            }

                            # Create result object
                            $outputFileName = if ($BatchSize -gt 1) { "Batch $batchIndex ($($batchFilesToProcess.Count) files)" } else { [System.IO.Path]::GetFileName($targetFile) }
                            $outputFullPath = if ($BatchSize -gt 1) { "Batch: $($batchFilesToProcess -join ', ')" } else { $targetFile }

                            [PSCustomObject]@{
                                FileName   = $outputFileName
                                FullPath   = $outputFullPath
                                Tool       = $currentTool
                                Model      = if ($modelToUse) { $modelToUse } else { 'Default' }
                                Result     = $capturedOutput
                                StartTime  = $startTime
                                EndTime    = $endTime = Get-Date
                                Duration   = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                                Success    = ($toolExitCode -eq 0)
                                BatchFiles = if ($BatchSize -gt 1) { $batchFilesToProcess } else { @($targetFile) }
                            }

                            Write-PSFMessage -Level Verbose -Message "Tool exited with code: $toolExitCode"
                            if ($toolExitCode -eq 0) {
                                Write-PSFMessage -Level Verbose -Message "Successfully processed: $batchDesc"
                            } else {
                                Write-PSFMessage -Level Error -Message "Failed to process $batchDesc (exit code $toolExitCode)"
                            }

                        } catch {
                            Write-PSFMessage -Level Error -Message "Error processing batch: $_"
                        } finally {
                            # Clean up Codex environment variable
                            if ($currentTool -eq 'Codex') {
                                Write-PSFMessage -Level Verbose -Message "Cleaning up RUST_LOG environment variable"
                                if (Test-Path Env:RUST_LOG) {
                                    Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
                                }
                            }

                            # Restore location after processing each batch
                            if ($targetDirectory -and (Test-Path $targetDirectory)) {
                                Pop-Location
                                Write-PSFMessage -Level Verbose -Message "Restored location after processing batch"
                            }
                        }

                        # Check for errors and track for bail-out (sequential mode)
                        if ($toolExitCode -ne 0) {
                            $resultText = if ($capturedOutput) { $capturedOutput | Out-String } else { '' }
                            $trackingParams = @{
                                ResultText      = $resultText
                                Success         = $false
                                MaxErrors       = $MaxErrors
                                MaxTokenErrors  = $MaxTokenErrors
                                ErrorCount      = [ref]$script:errorCount
                                TokenErrorCount = [ref]$script:tokenErrorCount
                            }
                            $tracking = Update-ErrorTracking @trackingParams

                            if ($tracking.ShouldBailOut) {
                                $script:bailedOut = $true
                            }
                        }

                        # Apply delay after processing each batch (if not the last batch)
                        if ($DelaySeconds -gt 0 -and $batchIndex -lt $batches.Count) {
                            Write-PSFMessage -Level Verbose -Message "Waiting $DelaySeconds seconds before processing next batch..."
                            Start-Sleep -Seconds $DelaySeconds
                        }
                    } # End of foreach ($batch in $batches)
                } # End of sequential processing

                Write-Progress -Activity "Processing with $currentTool" -Completed

            } finally {
                # No additional cleanup needed - parallel execution handles its own cleanup
            }

            # Apply delay between tools when using -Tool All (if not the last tool)
            if ($DelaySeconds -gt 0 -and $toolsToRun.Count -gt 1 -and $currentTool -ne $toolsToRun[-1]) {
                Write-PSFMessage -Level Verbose -Message "Waiting $DelaySeconds seconds before processing with next tool..."
                Start-Sleep -Seconds $DelaySeconds
            }
        } # End of foreach ($currentTool in $toolsToRun)

        Write-PSFMessage -Level Verbose -Message "All files processed"
        Write-PSFMessage -Level Debug -Message "Processing complete."
    }
}
