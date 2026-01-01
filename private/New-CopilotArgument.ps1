function New-CopilotArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [bool]$IgnoreInstructions,
        [string]$WorkingDirectory,
        [string]$PromptFilePath,
        [string[]]$ContextFilePaths
    )

    Write-PSFMessage -Level Verbose -Message "Building GitHub Copilot CLI arguments..."
    $arguments = @()

    # Always add --allow-all-tools for non-interactive mode
    Write-PSFMessage -Level Debug -Message "Adding allow-all-tools flag"
    $arguments += '--allow-all-tools'

    if ($IgnoreInstructions) {
        Write-PSFMessage -Level Debug -Message "Adding no-custom-instructions flag to bypass AGENTS.md loading"
        $arguments += '--no-custom-instructions'
    }

    # Add directory access first (must come before other flags for proper permission handling)
    # Collect unique directories to avoid duplicates
    $directoriesToAdd = @()

    if ($WorkingDirectory) {
        Write-PSFMessage -Level Debug -Message "Adding working directory: $WorkingDirectory"
        $directoriesToAdd += $WorkingDirectory
    }

    if ($TargetFile) {
        $parentDir = Split-Path -Parent $TargetFile
        Write-PSFMessage -Level Debug -Message "Adding target file parent directory: $parentDir"
        $directoriesToAdd += $parentDir

        if (-not (Test-Path $parentDir/.git)) {
            $grandparentDir = Split-Path -Parent $parentDir
            Write-PSFMessage -Level Debug -Message "Adding target file grandparent directory: $grandparentDir"
            $directoriesToAdd += $grandparentDir
        }
    }

    # Add parent directories from prompt file
    if ($PromptFilePath) {
        if (Test-Path $PromptFilePath) {
            # Resolve to full path
            $resolvedPromptFile = (Resolve-Path $PromptFilePath).Path
            $promptParentDir = Split-Path -Parent $resolvedPromptFile
            Write-PSFMessage -Level Debug -Message "Adding prompt file parent directory: $promptParentDir (resolved from: $PromptFilePath)"
            $directoriesToAdd += $promptParentDir
        } else {
            Write-PSFMessage -Level Warning -Message "Prompt file path not found and will be skipped: $PromptFilePath"
        }
    }

    # Add parent directories from context files
    if ($ContextFilePaths -and $ContextFilePaths.Count -gt 0) {
        foreach ($contextFile in $ContextFilePaths) {
            # Validate and resolve the context file path
            if (Test-Path $contextFile) {
                # Resolve to full path
                $resolvedContextFile = (Resolve-Path $contextFile).Path
                $contextParentDir = Split-Path -Parent $resolvedContextFile
                Write-PSFMessage -Level Debug -Message "Adding context file parent directory: $contextParentDir (resolved from: $contextFile)"
                $directoriesToAdd += $contextParentDir
            } else {
                Write-PSFMessage -Level Warning -Message "Context file path not found and will be skipped: $contextFile"
            }
        }
    }

    # Add unique directories to arguments
    $uniqueDirs = $directoriesToAdd | Select-Object -Unique
    foreach ($dir in $uniqueDirs) {
        $arguments += '--add-dir', $dir
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Debug -Message "Setting log level to debug"
        $arguments += '--log-level', 'debug'
    } elseif ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Debug -Message "Setting log level to info"
        $arguments += '--log-level', 'info'
    }

    if ($Model) {
        Write-PSFMessage -Level Debug -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($Message) {
        Write-PSFMessage -Level Debug -Message "Adding message prompt"

        # For file editing, prepend the target file reference at the very beginning
        # so Copilot knows which file to edit before reading the instructions
        if ($TargetFile) {
            $Message = "@$TargetFile`n`n$Message"
            Write-PSFMessage -Level Debug -Message "Prepended target file to message: @$TargetFile"
        }

        $arguments += '-p', $Message
    }

    Write-PSFMessage -Level Verbose -Message "Copilot arguments built: $($arguments -join ' ')"
    return $arguments
}
