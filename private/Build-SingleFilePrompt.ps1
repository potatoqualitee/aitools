function Build-SingleFilePrompt {
    <#
    .SYNOPSIS
        Builds a prompt for single file processing with auto-injection.

    .DESCRIPTION
        Builds the full prompt for processing a single file. Handles Copilot's @ prefix
        syntax, auto-injects file paths into prompts that don't reference them, and adds
        static and dynamic context files.

    .PARAMETER BasePrompt
        The base prompt text.

    .PARAMETER FilePath
        The file path to process.

    .PARAMETER StaticContextFiles
        Array of static context file paths to include.

    .PARAMETER ContextFilter
        Optional scriptblock for deriving dynamic context files.

    .PARAMETER ContextFilterBase
        Base directories to search for derived context files.

    .PARAMETER ToolName
        The AI tool being used (e.g., Claude, Aider, Copilot).

    .PARAMETER ReasoningEffort
        Optional reasoning effort level for Claude (low, medium, high).

    .PARAMETER PromptFilePath
        The original prompt file path (if prompt came from a file).

    .PARAMETER PSCmdlet
        The PSCmdlet object for ShouldProcess support.

    .OUTPUTS
        [hashtable] with keys:
        - FullPrompt: The complete prompt with context
        - TargetFile: The file being processed
        - TargetDirectory: The directory of the file

    .EXAMPLE
        $params = @{
            BasePrompt = "Add error handling"
            FilePath   = "script.ps1"
            ToolName   = "Claude"
        }
        $result = Build-SingleFilePrompt @params
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$BasePrompt,

        [Parameter(Mandatory)]
        [string]$FilePath,

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
        [string]$PromptFilePath,

        [Parameter()]
        [System.Management.Automation.PSCmdlet]$PSCmdlet
    )

    $targetFile = $FilePath
    $targetDirectory = Split-Path $targetFile -Parent

    # For GitHub Copilot, use @ prefix to tell it to read files directly
    if ($ToolName -eq 'Copilot') {
        # Check if the prompt was originally a file path (has the "(File: ...)" suffix)
        if ($BasePrompt -match '\(File: (.+)\)$') {
            # Extract the original prompt file path
            $extractedPromptFile = $Matches[1]
            # Use @ prefix for both files, with explicit instruction about which file to edit
            $fullPrompt = "Read the instructions from @$extractedPromptFile and apply them to @$FilePath. Edit and save the changes to $FilePath."
        } else {
            # Prompt is plain text, so just include the target file with @ prefix
            $fullPrompt = "@$FilePath`n`n$BasePrompt"
        }
    } else {
        $fullPrompt = $BasePrompt

        # Auto-inject file path into prompt if not already present (for other tools)
        $fileNameOnly = [System.IO.Path]::GetFileName($FilePath)
        $hasFileReference = $fullPrompt -match [regex]::Escape($FilePath) -or
                            $fullPrompt -match [regex]::Escape($fileNameOnly) -or
                            $fullPrompt -match '\$file'

        # Skip edit injection for image files
        $imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.ico', '.tiff', '.tif')
        $fileExtension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        $isImageFile = $imageExtensions -contains $fileExtension

        if (-not $hasFileReference -and -not $isImageFile) {
            $editInstruction = "TARGET FILE TO EDIT: $FilePath`nEDIT THIS FILE AND WRITE IT TO DISK."
            $fullPrompt += "`n`n$editInstruction"
            Write-PSFMessage -Level Verbose -Message "File path not detected in prompt, appended: $editInstruction"
        }
    }

    # Add static context files (not for Aider - it handles context differently)
    if ($ToolName -ne 'Aider' -and $StaticContextFiles -and $StaticContextFiles.Count -gt 0) {
        Write-PSFMessage -Level Verbose -Message "Building combined prompt with $($StaticContextFiles.Count) static context file(s)"
        foreach ($ctxFile in $StaticContextFiles) {
            if (Test-Path $ctxFile) {
                $content = Get-Content -Path $ctxFile -Raw
                $fullPrompt += "`n`n--- Context from $($ctxFile) ---`n$content"
                Write-PSFMessage -Level Verbose -Message "Added static context from: $ctxFile"
            } else {
                Write-PSFMessage -Level Warning -Message "Context file not found: $ctxFile"
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

    # Add dynamic context from ContextFilter for single file (not for Aider)
    if ($ToolName -ne 'Aider' -and $ContextFilter) {
        $dynamicParams = @{
            BasePrompt        = $fullPrompt
            InputFiles        = @($FilePath)
            ContextFilter     = $ContextFilter
            ContextFilterBase = $ContextFilterBase
            PSCmdlet          = $PSCmdlet
        }
        $dynamicResult = Add-DynamicContextToPrompt @dynamicParams

        $fullPrompt = $dynamicResult.Prompt
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

    return @{
        FullPrompt      = $fullPrompt
        TargetFile      = $targetFile
        TargetDirectory = $targetDirectory
    }
}
