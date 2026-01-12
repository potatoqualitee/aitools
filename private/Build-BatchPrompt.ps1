function Build-BatchPrompt {
    <#
    .SYNOPSIS
        Builds a combined prompt for batch file processing.

    .DESCRIPTION
        Combines multiple files into a single prompt for batch processing. Includes
        static context files, dynamic context from ContextFilter, and file contents.
        Used when BatchSize > 1 to reduce API calls.

    .PARAMETER BasePrompt
        The base prompt text.

    .PARAMETER FilesToProcess
        Array of file paths to include in the batch.

    .PARAMETER StaticContextFiles
        Array of static context file paths to include.

    .PARAMETER ContextFilter
        Optional scriptblock for deriving dynamic context files.

    .PARAMETER ContextFilterBase
        Base directories to search for derived context files.

    .PARAMETER ToolName
        The AI tool being used (e.g., Claude, Aider). Aider handles context differently.

    .PARAMETER ReasoningEffort
        Optional reasoning effort level for Claude (low, medium, high).

    .PARAMETER PSCmdlet
        The PSCmdlet object for ShouldProcess support.

    .OUTPUTS
        [hashtable] with keys:
        - FullPrompt: The complete prompt with all context and files
        - TargetFile: The first file in the batch (used for directory context)
        - TargetDirectory: The directory of the first file

    .EXAMPLE
        $params = @{
            BasePrompt     = "Translate these files"
            FilesToProcess = @("file1.md", "file2.md")
            ToolName       = "Claude"
        }
        $result = Build-BatchPrompt @params
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$BasePrompt,

        [Parameter(Mandatory)]
        [string[]]$FilesToProcess,

        [Parameter()]
        [string[]]$StaticContextFiles,

        [Parameter()]
        [scriptblock]$ContextFilter,

        [Parameter()]
        [string[]]$ContextFilterBase,

        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', '')]
        [string]$ReasoningEffort,

        [Parameter()]
        [System.Management.Automation.PSCmdlet]$PSCmdlet
    )

    Write-PSFMessage -Level Verbose -Message "BATCH MODE: Combining $($FilesToProcess.Count) files into a SINGLE API request"
    $fullPrompt = $BasePrompt

    # Add static context files (not for Aider - it handles context differently)
    if ($ToolName -ne 'Aider' -and $StaticContextFiles -and $StaticContextFiles.Count -gt 0) {
        Write-PSFMessage -Level Verbose -Message "Adding $($StaticContextFiles.Count) static context file(s) to batch prompt"
        foreach ($ctxFile in $StaticContextFiles) {
            if (Test-Path $ctxFile) {
                $content = Get-Content -Path $ctxFile -Raw
                $fullPrompt += "`n`n--- Context from $($ctxFile) ---`n$content"
                Write-PSFMessage -Level Verbose -Message "Added static context: $ctxFile"
            }
        }

        # If context is a single JSON file, append instruction for raw JSON output
        $existingContextFiles = @($StaticContextFiles | Where-Object { Test-Path $_ })
        if ($existingContextFiles.Count -eq 1) {
            $singleContextFile = $existingContextFiles[0]
            if ([System.IO.Path]::GetExtension($singleContextFile).ToLower() -eq '.json') {
                $script:singleJson = $true
                $jsonInstruction = "IMPORTANT: Output raw JSON only - no markdown code fences, no backticks, no explanation. Response must start with { and end with } for direct parsing by ConvertFrom-Json. Follow the schema EXACTLY - use only the property names defined in the schema, no additional properties."
                $fullPrompt += "`n`n$jsonInstruction"
                Write-PSFMessage -Level Verbose -Message "Single JSON context detected - appended: $jsonInstruction"
            } else {
                $script:singleJson = $false
            }
        } else {
            $script:singleJson = $false
        }
    } else {
        $script:singleJson = $false
    }

    # Add dynamic context files from ContextFilter (not for Aider)
    if ($ToolName -ne 'Aider' -and $ContextFilter) {
        $dynamicParams = @{
            BasePrompt        = $fullPrompt
            InputFiles        = $FilesToProcess
            ContextFilter     = $ContextFilter
            ContextFilterBase = $ContextFilterBase
            PSCmdlet          = $PSCmdlet
        }
        $dynamicResult = Add-DynamicContextToPrompt @dynamicParams

        $fullPrompt = $dynamicResult.Prompt
    }

    # Add all files in batch with their contents
    $fullPrompt += "`n`n=== FILES TO PROCESS ===`n"
    foreach ($fileInBatch in $FilesToProcess) {
        $fileContent = Get-Content -Path $fileInBatch -Raw -ErrorAction SilentlyContinue
        # Use full absolute path in the prompt for clarity
        $absolutePath = (Resolve-Path -Path $fileInBatch).Path
        $fullPrompt += "`n--- FILE: $absolutePath ---`n$fileContent`n"
        Write-PSFMessage -Level Verbose -Message "  - Added file to batch: $absolutePath"
    }

    Write-PSFMessage -Level Verbose -Message "Batch prompt ready: $($FilesToProcess.Count) files combined into single request"

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

    # For batch mode, use the first file as the "target" for tool arguments
    $targetFile = $FilesToProcess[0]
    $targetDirectory = Split-Path $targetFile -Parent

    return @{
        FullPrompt      = $fullPrompt
        TargetFile      = $targetFile
        TargetDirectory = $targetDirectory
    }
}
