function New-AiderArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [string]$EditMode,
        [string[]]$ContextFiles,
        [bool]$UsePermissionBypass,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    Write-PSFMessage -Level Verbose -Message "Building Aider arguments..."
    $arguments = @('--message', $Message)
    Write-PSFMessage -Level Debug -Message "Message: $Message"

    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Debug -Message "Adding permission bypass flag"
        $arguments += '--yes-always'
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Verbose'] -or $PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Debug -Message "Adding verbose flag"
        $arguments += '--verbose'
    }

    if ($Model) {
        Write-PSFMessage -Level Debug -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($ReasoningEffort) {
        Write-PSFMessage -Level Debug -Message "Using reasoning effort: $ReasoningEffort"
        $arguments += '--reasoning-effort', $ReasoningEffort
    }

    if ($EditMode) {
        Write-PSFMessage -Level Debug -Message "Edit mode: $EditMode"
        $editFlag = $script:ToolDefinitions['Aider'].EditModeMap[$EditMode]
        if ($editFlag) {
            $arguments += $editFlag  # Add array elements (flag and value)
        }
    }

    Write-PSFMessage -Level Debug -Message "Adding optimization flags: no-auto-commits, cache-prompts, no-pretty, no-show-model-warnings, no-browser, subtree-only, no-repo-map, skip-sanity-check-repo"
    $arguments += '--no-auto-commits'
    $arguments += '--cache-prompts'
    $arguments += '--no-pretty'
    $arguments += '--no-show-model-warnings'
    $arguments += '--no-browser'
    $arguments += '--subtree-only'
    $arguments += '--map-tokens', '0'  # Disable repo map (0 tokens)
    $arguments += '--skip-sanity-check-repo'

    # Configure output directory for Aider history and metadata files
    $outputDir = Get-PSFConfigValue -FullName "AITools.Aider.OutputDir" -Fallback $null
    if (-not $outputDir) {
        # Default to a temp directory if not configured
        $outputDir = Join-Path ([System.IO.Path]::GetTempPath()) "aitools-aider-output"
        if (-not (Test-Path $outputDir)) {
            Write-PSFMessage -Level Debug -Message "Creating default Aider output directory: $outputDir"
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
    }
    Write-PSFMessage -Level Debug -Message "Using Aider output directory: $outputDir"

    # Set input history file
    $inputHistoryFile = Join-Path $outputDir ".aider.input.history"
    $arguments += '--input-history-file', $inputHistoryFile

    # Set chat history file
    $chatHistoryFile = Join-Path $outputDir ".aider.chat.history.md"
    $arguments += '--chat-history-file', $chatHistoryFile

    # Set model settings file
    $modelSettingsFile = Join-Path $outputDir ".aider.model.settings.yml"
    $arguments += '--model-settings-file', $modelSettingsFile

    # Set model metadata file
    $modelMetadataFile = Join-Path $outputDir ".aider.model.metadata.json"
    $arguments += '--model-metadata-file', $modelMetadataFile

    # Set aiderignore file
    $aiderignoreFile = Join-Path $outputDir ".aiderignore"
    $arguments += '--aiderignore', $aiderignoreFile

    # Set env file
    $envFile = Join-Path $outputDir ".env"
    $arguments += '--env-file', $envFile

    if ($TargetFile) {
        Write-PSFMessage -Level Debug -Message "Target file: $TargetFile"
        $arguments += '--file', $TargetFile
    }

    if ($ContextFiles) {
        Write-PSFMessage -Level Debug -Message "Adding $($ContextFiles.Count) context file(s)"
        foreach ($ctx in $ContextFiles) {
            # Validate and resolve the context file path
            if (Test-Path $ctx) {
                # Resolve to full path
                $resolvedCtx = (Resolve-Path $ctx).Path
                Write-PSFMessage -Level Debug -Message "Context file: $resolvedCtx (resolved from: $ctx)"
                $arguments += '--read', $resolvedCtx
            } else {
                Write-PSFMessage -Level Warning -Message "Context file path not found and will be skipped: $ctx"
            }
        }
    }

    Write-PSFMessage -Level Verbose -Message "Aider arguments built: $($arguments -join ' ')"
    return $arguments
}
