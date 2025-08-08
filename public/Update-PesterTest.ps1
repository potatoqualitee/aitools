function Update-PesterTest {
    <#
    .SYNOPSIS
        Updates Pester tests to v5 format for module-specific commands.

    .DESCRIPTION
        Updates existing Pester tests to v5 format for module-specific commands. This function processes test files
        and converts them to use the newer Pester v5 parameter validation syntax. It skips files that have
        already been converted or exceed the specified size limit.

    .PARAMETER InputObject
        Array of objects that can be either file paths, FileInfo objects, or command objects (from Get-Command).
        If not specified, will process commands from the specified module.

    .PARAMETER First
        Specifies the maximum number of commands to process.

    .PARAMETER Skip
        Specifies the number of commands to skip before processing.

    .PARAMETER Limit
        Maximum number of items to process. Default: 5

    .PARAMETER PromptFilePath
        The path to the template file containing the prompt structure.
        Defaults to the prompt.md file in the module's prompts directory.

    .PARAMETER ContextFilePath
        The path to files containing additional context (conventions, examples, etc.).
        Defaults to style.md and migration.md files in the module's prompts directory.

    .PARAMETER MaxFileSize
        The maximum size of test files to process, in bytes. Files larger than this will be skipped.
        Defaults to 500kb.

    .PARAMETER Model
        The AI model to use. Overrides configured default.

    .PARAMETER Tool
        The AI coding tool to use.
        Valid values: ClaudeCode, Aider, Gemini, GitHubCopilot, Codex
        Default: ClaudeCode

    .PARAMETER Raw
        Run the command directly without capturing output or assigning to variables.
        Useful for interactive scenarios like Jupyter notebooks where output handling can cause issues.

    .NOTES
        Tags: Testing, Pester
        Author: Chrissy LeMaire

    .EXAMPLE
        PS C:/> Update-PesterTest
        Updates all eligible Pester tests to v5 format using default parameters.

    .EXAMPLE
        PS C:/> Update-PesterTest -Tool Aider -First 10 -Skip 5
        Updates 10 test files starting from the 6th command, skipping the first 5, using Aider.

    .EXAMPLE
        PS C:/> "C:/tests/Get-DbaDatabase.Tests.ps1" | Update-PesterTest
        Updates the specified test file to v5 format.

    .EXAMPLE
        PS C:/> Get-Command -Module dbatools -Name "*Database*" | Update-PesterTest
        Updates test files for all commands in dbatools module that match "*Database*".

    .EXAMPLE
        PS C:/> Get-ChildItem ./tests/Add-DbaRegServer.Tests.ps1 | Update-PesterTest -Verbose
        Updates the specific test file from a Get-ChildItem result.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias('FullName', 'Path', 'FilePath')]
        [PSObject[]]$InputObject,
        [int]$First = 10000,
        [int]$Skip,
        [int]$Limit = 5,
        [string]$PromptFilePath = (Resolve-Path "$script:ModuleRoot/prompts/prompt.md" -ErrorAction SilentlyContinue).Path,
        [string[]]$ContextFilePath = @(
            (Resolve-Path "$script:ModuleRoot/prompts/style.md" -ErrorAction SilentlyContinue).Path,
            (Resolve-Path "$script:ModuleRoot/prompts/migration.md" -ErrorAction SilentlyContinue).Path
        ),
        [int]$MaxFileSize = 500kb,
        [string]$Model,
        [string]$Tool,
        [switch]$Raw
    )
    begin {
        # Flag to track if initialization succeeded
        $script:initSucceeded = $false

        # Track modules we've attempted to load
        $script:attemptedModules = @{}

        # Use default tool if not specified
        if (-not $Tool) {
            $Tool = Get-PSFConfigValue -FullName 'AITools.DefaultTool' -Fallback $null
            if (-not $Tool) {
                Write-PSFMessage -Level Error -Message "No tool specified and no default tool configured. Run Initialize-AIToolDefault or specify -Tool parameter."
                return
            }
            Write-PSFMessage -Level Verbose -Message "Using default tool: $Tool"
        }

        Write-PSFMessage -Level Verbose -Message "Starting Update-PesterTest with tool: $Tool"

        # Check if piping input with Gemini - warn about potential output quirks
        $isPiping = $MyInvocation.PipelinePosition -gt 1 -or $MyInvocation.ExpectingInput
        $suppressWarning = Get-PSFConfigValue -FullName 'AITools.SuppressGeminiPipelineWarning' -Fallback $false

        # Load prompt template
        $promptTemplate = if ($PromptFilePath -and (Test-Path $PromptFilePath)) {
            Get-Content $PromptFilePath -Raw
        } else {
            Write-PSFMessage -Level Error -Message "Prompt template not found at $PromptFilePath"
            return
        }

        # Validate context files exist
        $validContextFiles = @()
        foreach ($contextPath in $ContextFilePath) {
            if ($contextPath -and (Test-Path $contextPath)) {
                $validContextFiles += $contextPath
                Write-PSFMessage -Level Verbose -Message "Added context file: $contextPath"
            } else {
                Write-PSFMessage -Level Warning -Message "Context file not found: $contextPath"
            }
        }

        $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters
        [System.Collections.ArrayList]$commandsToProcess = @()

        # Add counters for early filtering in the pipeline
        $pipelineIndex = 0
        $collectedCount = 0

        # Mark initialization as successful
        $script:initSucceeded = $true
    }

    process {
        # Skip processing if initialization failed
        if (-not $script:initSucceeded) {
            return
        }

        if ($InputObject) {
            foreach ($item in $InputObject) {
                $pipelineIndex++

                # EARLY FILTERING - reject before any expensive processing
                if ($Skip -gt 0 -and $pipelineIndex -le $Skip) {
                    Write-PSFMessage -Level Debug -Message "Skipping pipeline item $pipelineIndex"
                    continue
                }

                if ($First -lt 10000 -and $collectedCount -ge $First) {
                    Write-PSFMessage -Level Debug -Message "Reached First limit, ignoring remaining items"
                    continue
                }

                if ($collectedCount -ge $Limit) {
                    Write-PSFMessage -Level Debug -Message "Reached Limit, ignoring remaining items"
                    continue
                }

                $collectedCount++
                Write-PSFMessage -Level Debug -Message "Processing input object of type: $($item.GetType().FullName)"

                if ($item -is [System.Management.Automation.CommandInfo]) {
                    [void]$commandsToProcess.Add($item)
                } elseif ($item -is [System.IO.FileInfo]) {
                    $path = $item.FullName
                    Write-PSFMessage -Level Debug -Message "Processing FileInfo path: $path"
                    if ($path -like "*.Tests.ps1" -and (Test-Path $path)) {
                        $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($path) -replace '\.Tests$', ''

                        # Try to get the actual command to retrieve its parameters
                        $actualCommand = Get-Command -Name $cmdName -ErrorAction SilentlyContinue

                        # If command not found, try to determine and load the module
                        if (-not $actualCommand) {
                            # Try to extract module name from path (common pattern: ModuleName/tests/CommandName.Tests.ps1)
                            $pathParts = $path -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
                            $testsIndex = $pathParts.IndexOf('tests')
                            if ($testsIndex -gt 0) {
                                $potentialModuleName = $pathParts[$testsIndex - 1]

                                # Only attempt to load if we haven't tried this module before
                                if (-not $script:attemptedModules.ContainsKey($potentialModuleName)) {
                                    try {
                                        Import-Module $potentialModuleName -Verbose:$false -ErrorAction Stop
                                        Write-PSFMessage -Level Verbose -Message "Loaded module $potentialModuleName"
                                        $script:attemptedModules[$potentialModuleName] = $true
                                    } catch {
                                        Write-PSFMessage -Level Verbose -Message "Could not load module $potentialModuleName : $_"
                                        $script:attemptedModules[$potentialModuleName] = $false
                                    }
                                }

                                # Try to get the command again if module was successfully loaded
                                if ($script:attemptedModules[$potentialModuleName]) {
                                    $actualCommand = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
                                }
                            }
                        }

                        $testFileCommand = [PSCustomObject]@{
                            Name         = $cmdName
                            TestFilePath = $path
                            IsTestFile   = $true
                            Parameters   = if ($actualCommand) { $actualCommand.Parameters } else { @{} }
                            Source       = if ($actualCommand) { $actualCommand.Source } else { $null }
                        }
                        [void]$commandsToProcess.Add($testFileCommand)
                    } else {
                        Write-PSFMessage -Level Warning -Message "FileInfo object is not a valid test file: $path"
                    }
                } elseif ($item -is [string]) {
                    Write-PSFMessage -Level Debug -Message "Processing string path: $item"
                    try {
                        $resolvedItem = (Resolve-Path $item -ErrorAction Stop).Path
                        if ($resolvedItem -like "*.Tests.ps1" -and (Test-Path $resolvedItem)) {
                            $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedItem) -replace '\.Tests$', ''

                            # Try to get the actual command to retrieve its parameters
                            $actualCommand = Get-Command -Name $cmdName -ErrorAction SilentlyContinue

                            # If command not found, try to determine and load the module
                            if (-not $actualCommand) {
                                # Try to extract module name from path (common pattern: ModuleName/tests/CommandName.Tests.ps1)
                                $pathParts = $resolvedItem -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
                                $testsIndex = $pathParts.IndexOf('tests')
                                if ($testsIndex -gt 0) {
                                    $potentialModuleName = $pathParts[$testsIndex - 1]

                                    # Only attempt to load if we haven't tried this module before
                                    if (-not $script:attemptedModules.ContainsKey($potentialModuleName)) {
                                        try {
                                            Import-Module $potentialModuleName -ErrorAction Stop  -Verbose:$false
                                            Write-PSFMessage -Level Verbose -Message "Loaded module $potentialModuleName"
                                            $script:attemptedModules[$potentialModuleName] = $true
                                        } catch {
                                            Write-PSFMessage -Level Verbose -Message "Could not load module $potentialModuleName : $_"
                                            $script:attemptedModules[$potentialModuleName] = $false
                                        }
                                    }

                                    # Try to get the command again if module was successfully loaded
                                    if ($script:attemptedModules[$potentialModuleName]) {
                                        $actualCommand = Get-Command -Name $cmdName -ErrorAction SilentlyContinue
                                    }
                                }
                            }

                            $testFileCommand = [PSCustomObject]@{
                                Name         = $cmdName
                                TestFilePath = $resolvedItem
                                IsTestFile   = $true
                                Parameters   = if ($actualCommand) { $actualCommand.Parameters } else { @{} }
                                Source       = if ($actualCommand) { $actualCommand.Source } else { $null }
                            }
                            [void]$commandsToProcess.Add($testFileCommand)
                        } else {
                            Write-PSFMessage -Level Warning -Message "String path is not a valid test file: $resolvedItem"
                        }
                    } catch {
                        Write-PSFMessage -Level Warning -Message "Could not resolve path: $item"
                    }
                } else {
                    Write-PSFMessage -Level Warning -Message "Unsupported input type: $($item.GetType().FullName)"
                }
            }
        }
    }

    end {
        # Skip end processing if initialization failed
        if (-not $script:initSucceeded) {
            return
        }

        # Get commands from module if no input provided
        if (-not $commandsToProcess -and -not $PSBoundParameters.ContainsKey('InputObject')) {
            Write-PSFMessage -Level Verbose -Message "No input objects provided, processing would require module commands"
            return
        }

        if (-not $commandsToProcess) {
            Write-PSFMessage -Level Warning -Message "No commands to process"
            return
        }

        # Skip/First/Limit filtering already done in process block
        $totalCommands = $commandsToProcess.Count
        Write-PSFMessage -Level Debug -Message "Processing $totalCommands test file(s) with $Tool..."

        # Process each command
        $currentCommand = 0
        foreach ($command in $commandsToProcess) {
            $currentCommand++

            # Determine file path
            if ($command.IsTestFile) {
                $cmdName = $command.Name
                $filename = $command.TestFilePath
            } else {
                $cmdName = $command.Name

                # Get the module root from the command's source module
                $moduleRoot = (Get-Module $command.Source | Select-Object -First 1).ModuleBase

                if ($moduleRoot) {
                    # Search for tests within the module root
                    $getChildItemParams = @{
                        Path        = $moduleRoot
                        Recurse     = $true
                        Filter      = "$cmdName.Tests.ps1"
                        ErrorAction = 'SilentlyContinue'
                    }
                    $testFile = Get-ChildItem @getChildItemParams | Select-Object -First 1
                    $filename = $testFile.FullName
                }
            }

            Write-PSFMessage -Level Debug -Message "Processing command: $cmdName ($currentCommand/$totalCommands)"
            Write-PSFMessage -Level Verbose -Message "Test file path: $filename"

            # Validate file exists
            if (-not $filename -or -not (Test-Path $filename)) {
                Write-PSFMessage -Level Warning -Message "No tests found for $cmdName, file not found"
                continue
            }

            # Check file size
            $fileSize = (Get-Item $filename).Length
            if ($fileSize -gt $MaxFileSize) {
                Write-PSFMessage -Level Warning -Message "Skipping $cmdName because file size ($fileSize bytes) exceeds limit ($MaxFileSize bytes)"
                continue
            }

            # Build prompt with command-specific information
            $parameters = if ($command.Parameters) {
                $command.Parameters.Values | Where-Object Name -notin $commonParameters
            } else {
                @()
            }

            $formattedFilename = $filename -replace '\\', '/'
            $cmdPrompt = $promptTemplate -replace "--FILEPATH--", $formattedFilename
            $cmdPrompt = $cmdPrompt -replace "--CMDNAME--", $cmdName
            $cmdPrompt = $cmdPrompt -replace "--PARMZ--", ($parameters.Name -join "`n")

            if ($PSCmdlet.ShouldProcess($filename, "Update Pester test to v5 format using $Tool")) {
                # Build Invoke-AITool parameters
                $invokeParams = @{
                    Tool    = $Tool
                    Prompt  = $cmdPrompt
                    Path    = $filename
                    Context = $validContextFiles
                }

                if ($Model) {
                    $invokeParams.Model = $Model
                }

                if ($Raw) {
                    $invokeParams.Raw = $true
                }

                Write-PSFMessage -Level Verbose -Message "Invoking $Tool to update test file"

                # Start the AI tool as a background job using ThreadJob for Jupyter notebook compatibility
                $job = Start-ThreadJob -Name $cmdName -ScriptBlock {
                    param($invokeParams, $moduleRoot, $verbosePreference, $debugPreference)

                    # Set preferences to match parent session
                    $VerbosePreference = $verbosePreference
                    $DebugPreference = $debugPreference

                    # Import the module in the job
                    Import-Module (Join-Path $moduleRoot "aitools.psd1") -Force -Verbose:$false

                    # Execute Invoke-AITool
                    Invoke-AITool @invokeParams
                } -ArgumentList $invokeParams, $script:ModuleRoot, $VerbosePreference, $DebugPreference

                # Track progress with elapsed time while job runs
                $startTime = Get-Date
                while ($job.State -in 'Running', 'NotStarted') {
                    $elapsed = (Get-Date) - $startTime
                    $elapsedString = "{0:00}:{1:00}:{2:00}" -f [Math]::Floor($elapsed.Hours), [Math]::Floor($elapsed.Minutes), [Math]::Floor($elapsed.Seconds)

                    $progressParams = @{
                        Activity        = "Refactoring with $Tool"
                        Status          = "$cmdName ($currentCommand/$totalCommands) - Elapsed: $elapsedString"
                        PercentComplete = ($currentCommand / $totalCommands) * 100
                    }
                    Write-Progress @progressParams

                    Start-Sleep -Seconds 1
                }

                # Output the result object if one was returned, excluding RunspaceId
                # In raw mode, Invoke-AITool returns early without creating a structured object
                if (-not $Raw) {
                    Receive-Job -Job $job -Wait -AutoRemoveJob | Select-Object -Property * -ExcludeProperty RunspaceId, PSComputerName, PSShowComputerName
                } elseif ($Raw) {
                    # In raw mode, just output whatever was returned without processing
                    Receive-Job -Job $job -Wait -AutoRemoveJob
                }
            }
        }

        Write-Progress -Activity "Refactoring with $Tool" -Completed
        Write-PSFMessage -Level Debug -Message "Processing complete. Updated $totalCommands file(s)."
    }
}
