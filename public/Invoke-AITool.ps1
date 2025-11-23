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
    #>
    [CmdletBinding()]
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
        [int]$BatchSize = 1
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
            try {
                # Check if we're in a git repository
                $null = git rev-parse --is-inside-work-tree 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-PSFMessage -Level Verbose -Message "Git repository detected, performing initial scan then per-file verification"

                    # Get and cache repo root
                    $script:cachedRepoRoot = git rev-parse --show-toplevel 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-PSFMessage -Level Warning -Message "Could not determine repo root. -SkipModified will be skipped."
                        $script:cachedRepoRoot = $null
                    } else {
                        $script:cachedRepoRoot = $script:cachedRepoRoot -replace '/', '\'
                        Write-PSFMessage -Level Verbose -Message "Cached repo root: $script:cachedRepoRoot"

                        # Get current branch name
                        $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-PSFMessage -Level Warning -Message "Could not determine current branch. -SkipModified will be skipped."
                        } else {
                            # Get the remote's default branch (what origin/HEAD points to)
                            $upstreamBranch = git symbolic-ref refs/remotes/origin/HEAD 2>&1 | ForEach-Object { $_ -replace 'refs/remotes/', '' }
                            if ($LASTEXITCODE -ne 0) {
                                Write-PSFMessage -Level Warning -Message "Could not determine remote default branch. -SkipModified will be skipped."
                            } else {
                                # Check if we're on the main/upstream branch (main, master, trunk, or whatever upstream points to)
                                $upstreamBranchName = $upstreamBranch -replace '^origin/', ''
                                $isOnMainBranch = $currentBranch -in @('main', 'master', 'trunk', $upstreamBranchName)

                                if ($isOnMainBranch) {
                                    Write-PSFMessage -Level Warning -Message "You are on the main branch '$currentBranch'. Using -CommitDepth $CommitDepth to check recent commit history for modified files."
                                }

                                Write-PSFMessage -Level Verbose -Message "Using remote default branch: $upstreamBranch"

                                # Store git context for per-file checking
                                $gitContext = @{
                                    UpstreamBranch = $upstreamBranch
                                    IsOnMainBranch = $isOnMainBranch
                                    CommitDepth = $CommitDepth
                                    CurrentBranch = $currentBranch
                                }

                                # Initial sweep: Build snapshot of all modified files (quick bulk check)
                                Write-PSFMessage -Level Verbose -Message "Performing initial sweep of modified files..."
                                $allModifiedFiles = @()

                                # Get uncommitted working tree changes
                                $workingTreeChanges = git diff --name-only 2>&1 | Where-Object { $_ -is [string] }
                                if ($LASTEXITCODE -eq 0 -and $workingTreeChanges) {
                                    $allModifiedFiles += $workingTreeChanges
                                    Write-PSFMessage -Level Verbose -Message "Found $(@($workingTreeChanges).Count) uncommitted working tree change(s)"
                                }

                                # Get staged changes
                                $stagedChanges = git diff --name-only --cached 2>&1 | Where-Object { $_ -is [string] }
                                if ($LASTEXITCODE -eq 0 -and $stagedChanges) {
                                    $allModifiedFiles += $stagedChanges
                                    Write-PSFMessage -Level Verbose -Message "Found $(@($stagedChanges).Count) staged change(s)"
                                }

                                # Get committed changes based on branch
                                if ($isOnMainBranch) {
                                    $recentCommitChanges = git log -n $CommitDepth --name-only --pretty=format: 2>&1 | Where-Object { $_ -is [string] -and $_.Trim() }
                                    if ($LASTEXITCODE -eq 0 -and $recentCommitChanges) {
                                        $allModifiedFiles += $recentCommitChanges
                                        Write-PSFMessage -Level Verbose -Message "Found $(@($recentCommitChanges).Count) file(s) modified in last $CommitDepth commit(s)"
                                    }
                                } else {
                                    $committedChanges = git diff --name-only "$upstreamBranch..HEAD" 2>&1 | Where-Object { $_ -is [string] }
                                    if ($LASTEXITCODE -eq 0 -and $committedChanges) {
                                        $allModifiedFiles += $committedChanges
                                        Write-PSFMessage -Level Verbose -Message "Found $(@($committedChanges).Count) committed but not pushed change(s)"
                                    }
                                }

                                # Convert to hashtable for O(1) lookups and normalize paths
                                if ($allModifiedFiles.Count -gt 0) {
                                    $allModifiedFiles | Select-Object -Unique | ForEach-Object {
                                        $filename = $_.Trim()
                                        if ($filename) {
                                            $resolvedPath = Join-Path $script:cachedRepoRoot $filename | Resolve-Path -ErrorAction SilentlyContinue
                                            if ($resolvedPath) {
                                                $normalizedPath = $resolvedPath.Path -replace '\\', '/'
                                                $initialModifiedSnapshot[$normalizedPath] = $true
                                            }
                                        }
                                    }
                                    Write-PSFMessage -Level Verbose -Message "Initial sweep: $($initialModifiedSnapshot.Count) modified files to potentially skip"
                                } else {
                                    Write-PSFMessage -Level Verbose -Message "Initial sweep: No modified files found"
                                }
                            }
                        }
                    }
                } else {
                    Write-PSFMessage -Level Warning -Message "-SkipModified specified but not in a git repository. Parameter will be ignored."
                }
            } catch {
                Write-PSFMessage -Level Warning -Message "Failed to setup git context: $_. -SkipModified will be ignored."
            }
        }

        # Set default prompt if none provided
        if (-not $Prompt) {
            $Prompt = "Convert this file according to the instructions."
            Write-PSFMessage -Level Verbose -Message "No prompt provided, using default: $Prompt"
        }

        # Note: Attachment validation moved to end{} block after imageAttachments are collected from pipeline

        # Process Prompt parameter - detect if it's a file object, file path, file pattern, or string
        # Track prompt file path for copilot --add-dir support
        $promptFilePath = $null
        $promptText = if ($Prompt -is [System.IO.FileInfo] -or $Prompt -is [System.IO.FileSystemInfo]) {
            Write-PSFMessage -Level Verbose -Message "Prompt is a file object: $($Prompt.FullName)"
            if (Test-Path $Prompt.FullName) {
                $promptFilePath = $Prompt.FullName
                $content = Get-Content $Prompt.FullName -Raw
                # Append file path to content
                "$content`n`n(File: $($Prompt.FullName))"
            } else {
                Stop-PSFFunction -Message "Prompt file not found: $($Prompt.FullName)" -EnableException $true
                return
            }
        } elseif ($Prompt -is [string]) {
            # Check if it's a file pattern (contains wildcards)
            if ($Prompt -match '[\*\?]') {
                Write-PSFMessage -Level Verbose -Message "Prompt appears to be a file pattern: $Prompt"
                $matchedFiles = Get-ChildItem -Path $Prompt -ErrorAction SilentlyContinue | Where-Object $false -eq PSIsContainer

                if ($matchedFiles) {
                    Write-PSFMessage -Level Verbose -Message "Found $($matchedFiles.Count) file(s) matching pattern: $Prompt"
                    # For multiple files, use the first one as the prompt file path
                    $promptFilePath = $matchedFiles[0].FullName
                    # Combine content from all matched files
                    $combinedContent = ($matchedFiles | ForEach-Object {
                        $fileContent = Get-Content $_.FullName -Raw
                        "$fileContent`n`n(File: $($_.FullName))"
                    }) -join "`n`n---`n`n"
                    $combinedContent
                } else {
                    Write-PSFMessage -Level Verbose -Message "No files matched pattern, treating as plain string"
                    $Prompt
                }
            }
            # Check if it's a file path
            elseif ((Test-Path $Prompt -ErrorAction SilentlyContinue) -and -not (Test-Path $Prompt -PathType Container)) {
                Write-PSFMessage -Level Verbose -Message "Prompt is a file path: $Prompt"
                $promptFilePath = $Prompt
                $content = Get-Content $Prompt -Raw
                # Append file path to content
                "$content`n`n(File: $Prompt)"
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

        # Resolve tool alias to canonical name (e.g., "Code" -> "Claude", "Copilot" -> "Copilot")
        $Tool = Resolve-ToolAlias -ToolName $Tool

        Write-PSFMessage -Level Verbose -Message "Starting Invoke-AITool with tool: $Tool"

        # Handle "All" tool selection - get all available tools
        $toolsToRun = @()
        if ($Tool -eq 'All') {
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
        $script:totalInputFiles = 0
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
            # Validate that all attachments have valid image extensions and exist
            $validImageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg')
            foreach ($attachmentPath in $imageAttachments) {
                $extension = [System.IO.Path]::GetExtension($attachmentPath).ToLower()
                if ($extension -notin $validImageExtensions) {
                    Stop-PSFFunction -Message "Invalid attachment file type: $attachmentPath. Only image files are supported: $($validImageExtensions -join ', ')" -EnableException $true
                    return
                }

                # Verify the file exists (for explicitly provided attachments, not piped files which are already resolved)
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

            # Build Select-Object parameters dynamically
            $selectParams = @{}
            if (Test-PSFParameterBinding -ParameterName 'Skip') { $selectParams['Skip'] = $Skip }
            if (Test-PSFParameterBinding -ParameterName 'First') { $selectParams['First'] = $First }
            if (Test-PSFParameterBinding -ParameterName 'Last') { $selectParams['Last'] = $Last }

            # Apply filtering using Select-Object (ensures exact same behavior)
            $filesToProcess = @($filesToProcess | Select-Object @selectParams)

            # Log filtering results
            Write-PSFMessage -Level Verbose -Message "File filtering applied: $originalCount → $($filesToProcess.Count) file(s) (Skip:$Skip First:$First Last:$Last)"
            if ($filesToProcess.Count -ne $originalCount) {
                Write-PSFMessage -Level Verbose -Message "Filtered to $($filesToProcess.Count) of $originalCount file(s) based on -Skip/-First/-Last parameters"
            }
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

                # Add Claude reasoning trigger if needed
                if ($currentTool -eq 'Claude' -and $reasoningEffortToUse) {
                    $reasoningPhrase = switch ($reasoningEffortToUse) {
                        'low'    { 'think hard' }
                        'medium' { 'think harder' }
                        'high'   { 'ultrathink' }
                    }
                    Write-PSFMessage -Level Verbose -Message "Adding Claude reasoning trigger: $reasoningPhrase"
                    $fullPrompt += "`n`n$reasoningPhrase"
                }

                Write-PSFMessage -Level Verbose -Message "Building arguments for chat mode with $currentTool"
                $arguments = switch ($currentTool) {
                'Claude' {
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
                'Copilot' {
                    $argumentParams = @{
                        Message             = $fullPrompt
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        WorkingDirectory    = (Get-Location).Path
                        PromptFilePath      = $promptFilePath
                        ContextFilePaths    = $contextFiles
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
                    if ($imageAttachments.Count -gt 0) {
                        $argumentParams['Attachment'] = $imageAttachments
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
                        $env:LITELLM_NUM_RETRIES = '0'

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
                    $env:LITELLM_NUM_RETRIES = '0'

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = {
                        $outFileParams = @{
                            FilePath = $tempOutputFile
                            Encoding = 'utf8'
                        }
                        # Use Tee-Object to both write to file AND return output for error checking
                        & $toolDef.Command @arguments *>&1 | Tee-Object @outFileParams
                    }.GetNewClosure()

                    $capturedOutput = Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Aider chat mode"
                    $toolExitCode = $LASTEXITCODE

                    # capturedOutput is already populated from Invoke-WithRetry
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    # Convert output to string if needed
                    if ($capturedOutput -is [array]) {
                        $capturedOutput = $capturedOutput | Out-String
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
                        Success      = ($toolExitCode -eq 0)
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

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = [ScriptBlock]::Create(@"
& '$($toolDef.Command)' $($arguments | ForEach-Object { if ($_ -match '\s') { "'$($_.Replace("'", "''"))'" } else { $_ } }) *>&1 | Out-File -FilePath '$tempOutputFile' -Encoding utf8
"@)

                    Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Codex chat mode"
                    $toolExitCode = $LASTEXITCODE

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    # Determine filename/path for output - use image attachment if present, otherwise chat mode
                    $outputFileName = if ($imageAttachments.Count -gt 0) {
                        [System.IO.Path]::GetFileName($imageAttachments[0])
                    } else {
                        'N/A (Chat Mode)'
                    }
                    $outputFullPath = if ($imageAttachments.Count -gt 0) {
                        $imageAttachments[0]
                    } else {
                        'N/A (Chat Mode)'
                    }

                    [PSCustomObject]@{
                        FileName     = $outputFileName
                        FullPath     = $outputFullPath
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($toolExitCode -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        $modeDesc = if ($imageAttachments.Count -gt 0) { "image processing" } else { "chat mode" }
                        Write-PSFMessage -Level Verbose -Message "Codex $modeDesc completed successfully"
                    } else {
                        $modeDesc = if ($imageAttachments.Count -gt 0) { "image processing" } else { "chat mode" }
                        Write-PSFMessage -Level Error -Message "Codex $modeDesc failed (exit code $LASTEXITCODE)"
                    }
                } elseif ($currentTool -eq 'Cursor') {
                    Write-PSFMessage -Level Verbose -Message "Executing Cursor in chat mode (prompt in arguments)"

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = {
                        & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
                    }.GetNewClosure()

                    Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Cursor chat mode"
                    $toolExitCode = $LASTEXITCODE

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
                        Success      = ($toolExitCode -eq 0)
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Chat mode completed successfully"
                    } else {
                        Write-PSFMessage -Level Error -Message "Chat mode failed (exit code $LASTEXITCODE)"
                    }
                } else {
                    Write-PSFMessage -Level Verbose -Message "Piping prompt to $currentTool in chat mode"

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = {
                        $fullPrompt | & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
                    }.GetNewClosure()

                    Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$currentTool chat mode"
                    $toolExitCode = $LASTEXITCODE

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
                        Success      = ($toolExitCode -eq 0)
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
                    if (Test-Path Env:RUST_LOG) {
                        Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
                    }
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

        # Warn if MaxThreads is higher than default (may cause API rate limiting)
        if ($MaxThreads -gt 3) {
            Write-PSFMessage -Level Warning -Message "Using $MaxThreads concurrent threads. This may trigger API rate limits depending on your service provider's quotas."
            Write-Warning "Using $MaxThreads threads may cause API rate limiting. Consider reducing -MaxThreads if you encounter throttling errors."
        }

        # PARALLEL PROCESSING: Default behavior for 4+ files/batches (unless -NoParallel is specified)
        # Sequential processing for 1-3 files/batches, or when -NoParallel is used
        # (Many AI CLI tools have rate limits and don't handle high concurrency well)
        # When BatchSize > 1, parallelization happens at the batch level (not individual files)
        # This combines token savings (batched files) with speed (parallel batches)
        $pool = $null
        $runspaces = @()

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
                if ($BatchSize -gt 1) {
                    Write-PSFMessage -Level Verbose -Message "Parallel batch mode enabled: $($filesToProcess.Count) files in $($batches.Count) batches - creating runspace pool with max $MaxThreads threads"
                } else {
                    Write-PSFMessage -Level Verbose -Message "Parallel mode enabled for $($filesToProcess.Count) files - creating runspace pool with max $MaxThreads threads"
                }
                $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
                $pool.ApartmentState = "MTA"
                $pool.Open()
            } else {
                if ($NoParallel) {
                    Write-PSFMessage -Level Verbose -Message "Sequential processing enforced by -NoParallel switch"
                } elseif ($BatchSize -gt 1) {
                    Write-PSFMessage -Level Verbose -Message "Sequential batch processing: $($filesToProcess.Count) files in $($batches.Count) batch(es) of up to $BatchSize file(s) each (parallel processing used for 4+ batches)"
                } else {
                    Write-PSFMessage -Level Verbose -Message "Sequential processing (only $($filesToProcess.Count) file(s), parallel is used for 4+ files)"
                }
            }

            $fileIndex = 0
            $totalFiles = $filesToProcess.Count

            # If parallel mode is enabled and we have multiple batches, use runspaces
            if ($shouldUseParallel -and $pool) {
            if ($BatchSize -gt 1) {
                Write-PSFMessage -Level Verbose -Message "Processing $totalFiles files in $($batches.Count) batches in parallel (max $MaxThreads concurrent batches)"
            } else {
                Write-PSFMessage -Level Verbose -Message "Processing $totalFiles files in parallel (max $MaxThreads concurrent)"
            }

            # Track start time for parallel execution timing
            $parallelStartTime = Get-Date
            $allDurations = [System.Collections.ArrayList]::new()

            # Get the module path for loading in runspaces
            $modulePsmPath = Join-Path $script:ModuleRoot "aitools.psm1"

            # Create scriptblock for parallel execution - just call Invoke-AITool recursively with batch
            $scriptblock = {
                param(
                    $ModulePath,
                    $BatchFiles,
                    $Prompt,
                    $Tool,
                    $Context,
                    $Model,
                    $ReasoningEffort,
                    $DisableRetry,
                    $MaxRetryMinutes,
                    $SkipModified,
                    $BatchSize
                )

                # Set environment variables for LiteLLM (used by Aider) in this runspace
                # Disable LiteLLM's internal retry mechanism since we handle retries ourselves
                $env:LITELLM_NUM_RETRIES = '0'

                # Import the module from the provided path
                Import-Module $ModulePath -ErrorAction Stop

                # Build parameters for recursive call
                $params = @{
                    Path = $BatchFiles
                    Prompt = $Prompt
                    Tool = $Tool
                    NoParallel = $true  # Force sequential processing in worker threads
                    BatchSize = $BatchSize  # Preserve batch size for proper batching in worker thread
                }

                if ($Context) { $params['Context'] = $Context }
                if ($Model) { $params['Model'] = $Model }
                if ($ReasoningEffort) { $params['ReasoningEffort'] = $ReasoningEffort }
                if ($DisableRetry) { $params['DisableRetry'] = $DisableRetry }
                if ($MaxRetryMinutes) { $params['MaxRetryMinutes'] = $MaxRetryMinutes }
                if ($SkipModified) { $params['SkipModified'] = $SkipModified }

                # Call Invoke-AITool recursively with -NoParallel to prevent nested parallelization
                Invoke-AITool @params
            }

            # Create and start runspaces for each batch
            $batchIndex = 0
            foreach ($batch in $batches) {
                $batchIndex++
                $batchFileNames = ($batch | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
                Write-PSFMessage -Level Debug -Message "Queuing batch $batchIndex of $($batches.Count) for parallel processing: $batchFileNames"
                $progressParams = @{
                    Activity        = "Starting parallel processing with $currentTool"
                    Status          = "Queuing batch $batchIndex/$($batches.Count) ($($batch.Count) file(s))"
                    PercentComplete = ($batchIndex / $batches.Count) * 100
                }
                Write-Progress @progressParams

                $runspace = [PowerShell]::Create()
                $null = $runspace.AddScript($scriptblock)
                $null = $runspace.AddArgument($modulePsmPath)        # ModulePath
                $null = $runspace.AddArgument($batch)                # BatchFiles (array)
                $null = $runspace.AddArgument($promptText)           # Prompt
                $null = $runspace.AddArgument($currentTool)          # Tool
                $null = $runspace.AddArgument($contextFiles)         # Context
                $null = $runspace.AddArgument($modelToUse)           # Model
                $null = $runspace.AddArgument($reasoningEffortToUse) # ReasoningEffort
                $null = $runspace.AddArgument($DisableRetry)         # DisableRetry
                $null = $runspace.AddArgument($MaxRetryMinutes)      # MaxRetryMinutes
                $null = $runspace.AddArgument($SkipModified)         # SkipModified
                $null = $runspace.AddArgument($BatchSize)            # BatchSize
                $runspace.RunspacePool = $pool

                $runspaces += [PSCustomObject]@{
                    Pipe = $runspace
                    Status = $runspace.BeginInvoke()
                    Batch = $batch
                    Index = $batchIndex
                }
            }

            Write-PSFMessage -Level Verbose -Message "All runspaces started, waiting for completion and streaming results..."

            # Complete the queuing progress bar before starting the processing one
            Write-Progress -Activity "Starting parallel processing with $currentTool" -Completed

            # Update progress to show we're now processing (not queuing)
            $processingActivity = if ($BatchSize -gt 1) { "Processing batches in parallel with $currentTool" } else { "Processing files in parallel with $currentTool" }
            Write-Progress -Activity $processingActivity -Status "Waiting for results..." -PercentComplete 0

            # Poll runspaces and output results as they complete (streaming, not buffering)
            $completedBatchCount = 0
            $totalBatches = $batches.Count
            while ($runspaces.Count -gt 0) {
                foreach ($runspace in @($runspaces)) {
                    if ($runspace.Status.IsCompleted) {
                        try {
                            $result = $runspace.Pipe.EndInvoke($runspace.Status)
                            if ($result) {
                                $completedBatchCount++
                                if ($BatchSize -gt 1) {
                                    $batchFileNames = ($runspace.Batch | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
                                    Write-PSFMessage -Level Verbose -Message "Completed batch $completedBatchCount of $totalBatches ($($runspace.Batch.Count) files)"
                                    $progressParams = @{
                                        Activity        = $processingActivity
                                        Status          = "Completed batch: $batchFileNames ($completedBatchCount/$totalBatches)"
                                        PercentComplete = ($completedBatchCount / $totalBatches) * 100
                                    }
                                } else {
                                    $fileName = [System.IO.Path]::GetFileName($runspace.Batch[0])
                                    Write-PSFMessage -Level Verbose -Message "Completed $completedBatchCount of $totalBatches files"
                                    $progressParams = @{
                                        Activity        = $processingActivity
                                        Status          = "Completed: $fileName ($completedBatchCount/$totalBatches)"
                                        PercentComplete = ($completedBatchCount / $totalBatches) * 100
                                    }
                                }
                                Write-Progress @progressParams
                                # Store duration for time calculation and output result to pipeline immediately
                                # Result could be an array if batch contains multiple files
                                if ($result -is [array]) {
                                    foreach ($r in $result) {
                                        if ($r.Duration) {
                                            $null = $allDurations.Add($r.Duration.TotalSeconds)
                                        }
                                        $r
                                    }
                                } else {
                                    if ($result.Duration) {
                                        $null = $allDurations.Add($result.Duration.TotalSeconds)
                                    }
                                    $result
                                }
                            } else {
                                # Batch was skipped (likely by -SkipModified fresh check)
                                $completedBatchCount++
                                if ($BatchSize -gt 1) {
                                    $batchFileNames = ($runspace.Batch | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
                                    Write-PSFMessage -Level Verbose -Message "Skipped batch (fresh check): $batchFileNames"
                                    $progressParams = @{
                                        Activity        = $processingActivity
                                        Status          = "Skipped batch (modified): $batchFileNames ($completedBatchCount/$totalBatches)"
                                        PercentComplete = ($completedBatchCount / $totalBatches) * 100
                                    }
                                } else {
                                    $fileName = [System.IO.Path]::GetFileName($runspace.Batch[0])
                                    Write-PSFMessage -Level Verbose -Message "Skipped (fresh check): $($runspace.Batch[0])"
                                    $progressParams = @{
                                        Activity        = $processingActivity
                                        Status          = "Skipped (modified): $fileName ($completedBatchCount/$totalBatches)"
                                        PercentComplete = ($completedBatchCount / $totalBatches) * 100
                                    }
                                }
                                Write-Progress @progressParams
                            }
                        } catch {
                            $batchDesc = if ($BatchSize -gt 1) { "batch $($runspace.Index)" } else { $runspace.Batch[0] }
                            Write-PSFMessage -Level Error -Message "Error retrieving result for $batchDesc : $_"
                        } finally {
                            $runspace.Pipe.Dispose()
                            # Remove this specific runspace from the collection by comparing the runspace object itself
                            $runspaces = $runspaces | Where-Object { $_ -ne $runspace }
                        }
                    }
                }

                # Short sleep to avoid tight polling loop
                if ($runspaces.Count -gt 0) {
                    Start-Sleep -Milliseconds 100
                }
            }

            Write-PSFMessage -Level Verbose -Message "All parallel processing complete"
            Write-Progress -Activity $processingActivity -Completed

            # Calculate and report time savings from parallel execution
            $parallelEndTime = Get-Date
            $totalParallelTime = ($parallelEndTime - $parallelStartTime).TotalSeconds
            # Sum the duration of all completed tasks (already in seconds)
            $totalSequentialTime = ($allDurations | Measure-Object -Sum).Sum
            $timeSaved = $totalSequentialTime - $totalParallelTime
            $percentSaved = if ($totalSequentialTime -gt 0) { ($timeSaved / $totalSequentialTime) * 100 } else { 0 }

            Write-PSFMessage -Level Verbose -Message "Parallel execution completed in $([Math]::Round($totalParallelTime, 1))s vs estimated sequential time of $([Math]::Round($totalSequentialTime, 1))s"
            if ($timeSaved -gt 0) {
                Write-PSFMessage -Level Verbose -Message "Time saved: $([Math]::Round($timeSaved, 1))s ($([Math]::Round($percentSaved, 1))% faster)"
            }
        } else {
            # Sequential processing (batches already created above)
            Write-PSFMessage -Level Verbose -Message "Processing $totalFiles files in $($batches.Count) batch(es) of up to $BatchSize file(s) each"

            $batchIndex = 0
            foreach ($batch in $batches) {
                $batchIndex++

                # Filter out modified files from this batch if -SkipModified is enabled
                $batchFilesToProcess = @()
                foreach ($singleFile in $batch) {
                    $fileIndex++

                            # Stage 2: Fresh verification right before execution (if -SkipModified is enabled)
                    # This catches files modified by concurrent processes or previous file processing
                    if ($SkipModified -and $gitContext -and $script:cachedRepoRoot) {
                        Write-PSFMessage -Level Verbose -Message "Fresh check before processing: $singleFile"

                        # Quick single-file check using git diff with file path (fast, 2 git commands)
                        # Uses cached repo root to avoid repeated git rev-parse calls
                        $isModified = $false

                        try {
                            # Normalize both paths to forward slashes for comparison
                            $normalizedFile = $singleFile -replace '\\', '/'
                            $normalizedRepoRoot = $script:cachedRepoRoot -replace '\\', '/'
                            $escapedRepoRoot = [regex]::Escape($normalizedRepoRoot)

                            # Remove repo root prefix and leading slash to get relative path
                            $relativePath = $normalizedFile -replace "^$escapedRepoRoot", '' -replace '^/', ''

                            # Check uncommitted changes for this specific file
                            $workingTreeCheck = git diff --name-only -- $relativePath 2>&1
                            if ($LASTEXITCODE -eq 0 -and $workingTreeCheck) {
                                Write-PSFMessage -Level Verbose -Message "File has uncommitted changes: $singleFile"
                                $isModified = $true
                            }

                            # Check staged changes for this specific file
                            if (-not $isModified) {
                                $stagedCheck = git diff --name-only --cached -- $relativePath 2>&1
                                if ($LASTEXITCODE -eq 0 -and $stagedCheck) {
                                    Write-PSFMessage -Level Verbose -Message "File has staged changes: $singleFile"
                                    $isModified = $true
                                }
                            }
                        } catch {
                            Write-PSFMessage -Level Warning -Message "Error during fresh check: $_. Skipping file to be safe."
                            $isModified = $true
                        }

                        if ($isModified) {
                            Write-PSFMessage -Level Verbose -Message "Skipping file (fresh check): $singleFile"
                            continue
                        }
                    }

                    # Add file to batch for processing
                    $batchFilesToProcess += $singleFile
                }

                # Skip this batch if all files were filtered out
                if ($batchFilesToProcess.Count -eq 0) {
                    Write-PSFMessage -Level Verbose -Message "Batch $batchIndex skipped - all files were filtered"
                    continue
                }

                Write-PSFMessage -Level Debug -Message "Processing batch $batchIndex of $($batches.Count) with $($batchFilesToProcess.Count) file(s)"

                # Show progress for batch processing
                $batchFileNames = ($batchFilesToProcess | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
                $progressParams = @{
                    Activity        = "Processing with $currentTool"
                    Status          = "Batch $batchIndex/$($batches.Count): $batchFileNames"
                    PercentComplete = (($batchIndex - 1) / $batches.Count) * 100
                }
                Write-Progress @progressParams

                # Build combined prompt for the batch
                # For BatchSize > 1, include all files and their contents
                if ($BatchSize -gt 1) {
                    # Multi-file batch mode: include file contents in prompt
                    Write-PSFMessage -Level Verbose -Message "BATCH MODE: Combining $($batchFilesToProcess.Count) files into a SINGLE API request"
                    $fullPrompt = $promptText

                    # Add context files
                    if ($currentTool -ne 'Aider' -and $contextFiles.Count -gt 0) {
                        Write-PSFMessage -Level Verbose -Message "Adding $($contextFiles.Count) context file(s) to batch prompt"
                        foreach ($ctxFile in $contextFiles) {
                            if (Test-Path $ctxFile) {
                                $content = Get-Content -Path $ctxFile -Raw
                                $fullPrompt += "`n`n--- Context from $($ctxFile) ---`n$content"
                                Write-PSFMessage -Level Verbose -Message "Added context: $ctxFile"
                            }
                        }
                    }

                    # Add all files in batch with their contents
                    $fullPrompt += "`n`n=== FILES TO PROCESS ===`n"
                    foreach ($fileInBatch in $batchFilesToProcess) {
                        $fileContent = Get-Content -Path $fileInBatch -Raw -ErrorAction SilentlyContinue
                        # Use full absolute path in the prompt for clarity
                        $absolutePath = (Resolve-Path -Path $fileInBatch).Path
                        $fullPrompt += "`n--- FILE: $absolutePath ---`n$fileContent`n"
                        Write-PSFMessage -Level Verbose -Message "  - Added file to batch: $absolutePath"
                    }

                    Write-PSFMessage -Level Verbose -Message "Batch prompt ready: $($batchFilesToProcess.Count) files combined into single request"

                    # Add Claude reasoning trigger if needed
                    if ($currentTool -eq 'Claude' -and $reasoningEffortToUse) {
                        $reasoningPhrase = switch ($reasoningEffortToUse) {
                            'low'    { 'think hard' }
                            'medium' { 'think harder' }
                            'high'   { 'ultrathink' }
                        }
                        Write-PSFMessage -Level Verbose -Message "Adding Claude reasoning trigger: $reasoningPhrase"
                        $fullPrompt += "`n`n$reasoningPhrase"
                    }

                    # For batch mode, we use the first file as the "target" for tool arguments
                    # but the prompt contains all files
                    $targetFile = $batchFilesToProcess[0]
                    $targetDirectory = Split-Path $targetFile -Parent

                } else {
                    # Single file mode (original behavior)
                    $singleFile = $batchFilesToProcess[0]
                    $targetFile = $singleFile
                    $targetDirectory = Split-Path $targetFile -Parent

                    # For GitHub Copilot, use @ prefix to tell it to read files directly
                    if ($currentTool -eq 'Copilot') {
                        # Check if the prompt was originally a file path (has the "(File: ...)" suffix)
                        if ($promptText -match '\(File: (.+)\)$') {
                            # Extract the original prompt file path
                            $promptFilePath = $Matches[1]
                            # Use @ prefix for both files, with explicit instruction about which file to edit
                            $fullPrompt = "Read the instructions from @$promptFilePath and apply them to @$singleFile. Edit and save the changes to $singleFile."
                        } else {
                            # Prompt is plain text, so just include the target file with @ prefix
                            $fullPrompt = "@$singleFile`n`n$promptText"
                        }
                    } else {
                        $fullPrompt = $promptText

                        # Auto-inject file path into prompt if not already present (for other tools)
                        $fileNameOnly = [System.IO.Path]::GetFileName($singleFile)
                        $hasFileReference = $fullPrompt -match [regex]::Escape($singleFile) -or
                                            $fullPrompt -match [regex]::Escape($fileNameOnly) -or
                                            $fullPrompt -match '\$file'

                        if (-not $hasFileReference) {
                            Write-PSFMessage -Level Verbose -Message "File path not detected in prompt, injecting it"
                            $fullPrompt += "`n`nTARGET FILE TO EDIT: $singleFile`nEDIT THIS FILE AND WRITE IT TO DISK."
                        }
                    }

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

                    # Add Claude reasoning trigger if needed
                    if ($currentTool -eq 'Claude' -and $reasoningEffortToUse) {
                        $reasoningPhrase = switch ($reasoningEffortToUse) {
                            'low'    { 'think hard' }
                            'medium' { 'think harder' }
                            'high'   { 'ultrathink' }
                        }
                        Write-PSFMessage -Level Verbose -Message "Adding Claude reasoning trigger: $reasoningPhrase"
                        $fullPrompt += "`n`n$reasoningPhrase"
                    }
                }

                # Change to target file's directory
                if ($targetDirectory -and (Test-Path $targetDirectory)) {
                    Push-Location $targetDirectory
                    Write-PSFMessage -Level Verbose -Message "Changed to target directory: $targetDirectory"
                }

                Write-PSFMessage -Level Verbose -Message "Building arguments for $currentTool"
                $arguments = switch ($currentTool) {
                'Claude' {
                    $argumentParams = @{
                        TargetFile          = $targetFile
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
                        TargetFile          = $targetFile
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
                        TargetFile          = $targetFile
                        Message             = $promptText
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    New-GeminiArgument @argumentParams
                }
                'Copilot' {
                    $argumentParams = @{
                        TargetFile          = $targetFile
                        Message             = $promptText
                        Model               = $modelToUse
                        UsePermissionBypass = $permissionBypass
                        WorkingDirectory    = $targetDirectory
                        PromptFilePath      = $promptFilePath
                        ContextFilePaths    = $contextFiles
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
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
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
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
                        Verbose             = $VerbosePreference
                        Debug               = $DebugPreference
                    }
                    if ($reasoningEffortToUse) {
                        $argumentParams['ReasoningEffort'] = $reasoningEffortToUse
                    }
                    New-CursorArgument @argumentParams
                }
                'PSOPenAI' {
                    # PSOpenAI is handled via direct function call, not CLI arguments
                    # Return null to skip normal CLI execution flow
                    $null
                }
            }

            # Special handling for PSOpenAI (PowerShell module wrapper, not a CLI)
            if ($currentTool -eq 'PSOPenAI') {
                Write-PSFMessage -Level Verbose -Message "Invoking PSOpenAI module for image editing"
                try {
                    $psopenaiParams = @{
                        Prompt          = $promptText
                        InputImage      = $targetFile
                        GenerationType  = 'Image'
                    }
                    if ($modelToUse) {
                        $psopenaiParams['Model'] = $modelToUse
                    }

                    $result = Invoke-PSOpenAI @psopenaiParams

                    # Output result directly to pipeline
                    $result

                    # Skip to next batch, don't use normal CLI execution
                    continue
                } catch {
                    Write-PSFMessage -Level Error -Message "PSOpenAI invocation failed: $_"
                    continue
                }
            }

            Write-PSFMessage -Level Debug -Message "Final prompt sent to $currentTool :`n$fullPrompt"

            $startTime = Get-Date

            try {
                if ($Raw) {
                    Write-PSFMessage -Level Verbose -Message "Executing in raw mode (no output capturing)"
                    if ($currentTool -eq 'Aider') {
                        $originalOutputEncoding = [Console]::OutputEncoding
                        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                        $env:PYTHONIOENCODING = 'utf-8'
                        $env:LITELLM_NUM_RETRIES = '0'

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
                        Write-PSFMessage -Level Verbose -Message "Batch processed successfully"
                    } else {
                        Write-PSFMessage -Level Warning -Message "Failed to process batch (exit code: $exitCode)"
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
                    $env:LITELLM_NUM_RETRIES = '0'

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = {
                        $outFileParams = @{
                            FilePath = $tempOutputFile
                            Encoding = 'utf8'
                        }
                        # Use Tee-Object to both write to file AND return output for error checking
                        & $toolDef.Command @arguments *>&1 | Tee-Object @outFileParams
                    }.GetNewClosure()

                    $batchDesc = if ($BatchSize -gt 1) { "batch of $($batchFilesToProcess.Count) file(s)" } else { $targetFile }
                    $capturedOutput = Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Aider processing $batchDesc"
                    $toolExitCode = $LASTEXITCODE

                    # capturedOutput is already populated from Invoke-WithRetry
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    # Convert output to string if needed
                    if ($capturedOutput -is [array]) {
                        $capturedOutput = $capturedOutput | Out-String
                    }

                    # For batch mode, include batch info in output
                    $outputFileName = if ($BatchSize -gt 1) { "Batch $batchIndex ($($batchFilesToProcess.Count) files)" } else { [System.IO.Path]::GetFileName($targetFile) }
                    $outputFullPath = if ($BatchSize -gt 1) { "Batch: $($batchFilesToProcess -join ', ')" } else { $targetFile }

                    [PSCustomObject]@{
                        FileName     = $outputFileName
                        FullPath     = $outputFullPath
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($toolExitCode -eq 0)
                        BatchFiles   = if ($BatchSize -gt 1) { $batchFilesToProcess } else { @($targetFile) }
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $batchDesc"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $batchDesc (exit code $LASTEXITCODE)"
                    }

                    # Restore original encoding
                    [Console]::OutputEncoding = $originalOutputEncoding
                    Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
                } elseif ($currentTool -eq 'Codex') {
                    Write-PSFMessage -Level Verbose -Message "Executing Codex (prompt in arguments)"

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = [ScriptBlock]::Create(@"
& '$($toolDef.Command)' $($arguments | ForEach-Object { if ($_ -match '\s') { "'$($_.Replace("'", "''"))'" } else { $_ } }) *>&1 | Out-File -FilePath '$tempOutputFile' -Encoding utf8
"@)

                    $batchDesc = if ($BatchSize -gt 1) { "batch of $($batchFilesToProcess.Count) file(s)" } else { $targetFile }
                    Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Codex processing $batchDesc"
                    $toolExitCode = $LASTEXITCODE

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    $outputFileName = if ($BatchSize -gt 1) { "Batch $batchIndex ($($batchFilesToProcess.Count) files)" } else { [System.IO.Path]::GetFileName($targetFile) }
                    $outputFullPath = if ($BatchSize -gt 1) { "Batch: $($batchFilesToProcess -join ', ')" } else { $targetFile }

                    [PSCustomObject]@{
                        FileName     = $outputFileName
                        FullPath     = $outputFullPath
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($toolExitCode -eq 0)
                        BatchFiles   = if ($BatchSize -gt 1) { $batchFilesToProcess } else { @($targetFile) }
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $batchDesc"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $batchDesc (exit code $LASTEXITCODE)"
                    }
                } elseif ($currentTool -eq 'Cursor') {
                    Write-PSFMessage -Level Verbose -Message "Executing Cursor (prompt in arguments)"

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = {
                        & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
                    }.GetNewClosure()

                    $batchDesc = if ($BatchSize -gt 1) { "batch of $($batchFilesToProcess.Count) file(s)" } else { $targetFile }
                    Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "Cursor processing $batchDesc"
                    $toolExitCode = $LASTEXITCODE

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    $outputFileName = if ($BatchSize -gt 1) { "Batch $batchIndex ($($batchFilesToProcess.Count) files)" } else { [System.IO.Path]::GetFileName($targetFile) }
                    $outputFullPath = if ($BatchSize -gt 1) { "Batch: $($batchFilesToProcess -join ', ')" } else { $targetFile }

                    [PSCustomObject]@{
                        FileName     = $outputFileName
                        FullPath     = $outputFullPath
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($toolExitCode -eq 0)
                        BatchFiles   = if ($BatchSize -gt 1) { $batchFilesToProcess } else { @($targetFile) }
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $batchDesc"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $batchDesc (exit code $LASTEXITCODE)"
                    }
                } else {
                        Write-PSFMessage -Level Verbose -Message "Piping combined prompt to $currentTool"

                    # Wrap tool execution with retry logic
                    $executionScriptBlock = {
                        $fullPrompt | & $toolDef.Command @arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
                    }.GetNewClosure()

                    $batchDesc = if ($BatchSize -gt 1) { "batch of $($batchFilesToProcess.Count) file(s)" } else { $targetFile }
                    Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$currentTool processing $batchDesc"
                    $toolExitCode = $LASTEXITCODE

                    # Read output from temp file
                    $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8
                    Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue

                    # Filter out misleading Gemini warnings about unreadable directories
                    if ($currentTool -eq 'Gemini') {
                        $capturedOutput = $capturedOutput -replace '(?m)^\s*\[WARN\]\s+Skipping unreadable directory:.*?\n', ''
                    }

                    $outputFileName = if ($BatchSize -gt 1) { "Batch $batchIndex ($($batchFilesToProcess.Count) files)" } else { [System.IO.Path]::GetFileName($targetFile) }
                    $outputFullPath = if ($BatchSize -gt 1) { "Batch: $($batchFilesToProcess -join ', ')" } else { $targetFile }

                    [PSCustomObject]@{
                        FileName     = $outputFileName
                        FullPath     = $outputFullPath
                        Tool         = $currentTool
                        Model        = if ($modelToUse) { $modelToUse } else { 'Default' }
                        Result       = $capturedOutput
                        StartTime    = $startTime
                        EndTime      = $endTime = Get-Date
                        Duration     = [timespan]::FromSeconds([Math]::Floor(($endTime - $startTime).TotalSeconds))
                        Success      = ($toolExitCode -eq 0)
                        BatchFiles   = if ($BatchSize -gt 1) { $batchFilesToProcess } else { @($targetFile) }
                    }

                    Write-PSFMessage -Level Verbose -Message "Tool exited with code: $LASTEXITCODE"
                    if ($LASTEXITCODE -eq 0) {
                        Write-PSFMessage -Level Verbose -Message "Successfully processed: $batchDesc"
                    } else {
                        Write-PSFMessage -Level Error -Message "Failed to process $batchDesc (exit code $LASTEXITCODE)"
                    }
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

            # Apply delay after processing each batch (if not the last batch)
            if ($DelaySeconds -gt 0 -and $batchIndex -lt $batches.Count) {
                Write-PSFMessage -Level Verbose -Message "Waiting $DelaySeconds seconds before processing next batch..."
                Start-Sleep -Seconds $DelaySeconds
            }
            } # End of foreach ($batch in $batches)
            } # End of if ($shouldUseParallel) / else block

            Write-Progress -Activity "Processing with $currentTool" -Completed
        } finally {
            # Clean up runspace pool if it was created (runs even on Ctrl+C)
            if ($pool) {
                Write-PSFMessage -Level Verbose -Message "Cleaning up runspace pool (disposing runspaces and pool)"

                # Stop and dispose any remaining runspaces
                foreach ($runspace in $runspaces) {
                    if ($runspace.Pipe) {
                        try {
                            $runspace.Pipe.Stop()
                            $runspace.Pipe.Dispose()
                        } catch {
                            Write-PSFMessage -Level Debug -Message "Error disposing runspace: $_"
                        }
                    }
                }

                # Close and dispose the pool
                try {
                    $pool.Close()
                    $pool.Dispose()
                    Write-PSFMessage -Level Verbose -Message "Runspace pool cleaned up successfully"
                } catch {
                    Write-PSFMessage -Level Warning -Message "Error closing runspace pool: $_"
                }
            }
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
