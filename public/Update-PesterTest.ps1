function Update-PesterTest {
    <#
    .SYNOPSIS
        Updates Pester tests to v5 format for module-specific commands.

    .DESCRIPTION
        Updates existing Pester tests to v5 format for module-specific commands. This function processes test files
        and converts them to use the newer Pester v5 parameter validation syntax. It skips files that have
        already been converted or exceed the specified size limit.

        This is a thin wrapper around Invoke-AITool that handles test file discovery and validation.
        All AI tool parameters (Model, Tool, Raw, etc.) are passed through to Invoke-AITool.

    .PARAMETER InputObject
        Array of objects that can be either file paths, FileInfo objects, or command objects (from Get-Command).
        If not specified, will process commands from the specified module.

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
        The AI model to use. Passed through to Invoke-AITool.

    .PARAMETER Tool
        The AI coding tool to use. Passed through to Invoke-AITool.

    .PARAMETER Raw
        Run the command directly without capturing output. Passed through to Invoke-AITool.

    .NOTES
        Tags: Testing, Pester
        Author: Chrissy LeMaire

    .EXAMPLE
        PS C:/> Update-PesterTest
        Updates all eligible Pester tests to v5 format using default parameters.

    .EXAMPLE
        PS C:/> Update-PesterTest -Tool Aider
        Updates test files using Aider.

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
        # Track modules we've attempted to load
        $attemptedModules = @{}

        # Load prompt template
        $promptTemplate = if ($PromptFilePath -and (Test-Path $PromptFilePath)) {
            Get-Content $PromptFilePath -Raw
        } else {
            Write-PSFMessage -Level Warning -Message "Prompt template not found at $PromptFilePath, using default"
            "Update these Pester tests to v5 format"
        }

        # Validate context files exist
        $validContextFiles = @()
        foreach ($contextPath in $ContextFilePath) {
            if ($contextPath -and (Test-Path $contextPath)) {
                $validContextFiles += $contextPath
                Write-PSFMessage -Level Verbose -Message "Added context file: $contextPath"
            } elseif ($contextPath) {
                Write-PSFMessage -Level Warning -Message "Context file not found: $contextPath"
            }
        }

        # Collect test files from pipeline
        [System.Collections.ArrayList]$filesToProcess = @()
    }

    process {
        foreach ($item in $InputObject) {
            $testFilePath = $null

            if ($item -is [System.Management.Automation.CommandInfo]) {
                # CommandInfo - find the test file for this command
                $cmdName = $item.Name
                $moduleRoot = (Get-Module $item.Source | Select-Object -First 1).ModuleBase

                if ($moduleRoot) {
                    $testFile = Get-ChildItem -Path $moduleRoot -Recurse -Filter "$cmdName.Tests.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1
                    $testFilePath = $testFile.FullName
                }

                if (-not $testFilePath) {
                    Write-PSFMessage -Level Warning -Message "No test file found for command: $cmdName"
                    continue
                }
            } elseif ($item -is [System.IO.FileInfo]) {
                $testFilePath = $item.FullName
            } elseif ($item -is [string]) {
                try {
                    $testFilePath = (Resolve-Path $item -ErrorAction Stop).Path
                } catch {
                    Write-PSFMessage -Level Warning -Message "Could not resolve path: $item"
                    continue
                }
            } else {
                Write-PSFMessage -Level Warning -Message "Unsupported input type: $($item.GetType().FullName)"
                continue
            }

            # Validate it's a test file
            if ($testFilePath -notlike "*.Tests.ps1") {
                Write-PSFMessage -Level Warning -Message "Not a test file (must end with .Tests.ps1): $testFilePath"
                continue
            }

            # Validate file exists
            if (-not (Test-Path $testFilePath)) {
                Write-PSFMessage -Level Warning -Message "Test file not found: $testFilePath"
                continue
            }

            # Check file size
            $fileSize = (Get-Item $testFilePath).Length
            if ($fileSize -gt $MaxFileSize) {
                Write-PSFMessage -Level Warning -Message "Skipping $testFilePath - file size ($fileSize bytes) exceeds limit ($MaxFileSize bytes)"
                continue
            }

            [void]$filesToProcess.Add($testFilePath)
        }
    }

    end {
        if ($filesToProcess.Count -eq 0) {
            Write-PSFMessage -Level Warning -Message "No valid test files to process"
            return
        }

        Write-PSFMessage -Level Verbose -Message "Collected $($filesToProcess.Count) test file(s) to process"

        # Clean up prompt template - remove any placeholder lines
        $prompt = $promptTemplate -replace '--FILEPATH--.*', '' -replace '--CMDNAME--.*', '' -replace '--PARMZ--.*', ''

        # Build Invoke-AITool parameters
        $invokeParams = @{
            Prompt  = $prompt
            Path    = $filesToProcess
            Context = $validContextFiles
        }

        if ($Tool) {
            $invokeParams.Tool = $Tool
        }

        if ($Model) {
            $invokeParams.Model = $Model
        }

        if ($Raw) {
            $invokeParams.Raw = $true
        }

        # Call Invoke-AITool - it handles tool selection, retries, progress, etc.
        if ($PSCmdlet.ShouldProcess("$($filesToProcess.Count) test files", "Update Pester tests to v5 format")) {
            Invoke-AITool @invokeParams
        }
    }
}
