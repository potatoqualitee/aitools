function New-CodexArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [string]$WorkingDirectory,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort,
        [string[]]$Attachment
    )

    Write-PSFMessage -Level Verbose -Message "Building Codex CLI arguments..."
    $arguments = @('exec')

    # Set RUST_LOG environment variable for Codex
    if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Verbose -Message "Setting RUST_LOG to debug"
        $env:RUST_LOG = 'debug'
    } elseif ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Verbose -Message "Setting RUST_LOG to info"
        $env:RUST_LOG = 'info'
    }

    # Set working directory if provided (helps with workspace permissions)
    if ($WorkingDirectory) {
        Write-PSFMessage -Level Verbose -Message "Setting working directory: $WorkingDirectory"
        $arguments += '-C', $WorkingDirectory
    }

    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Verbose -Message "Using full-auto mode with bypass"
        # Note: --full-auto is supposed to set --sandbox workspace-write automatically,
        # but in practice it still defaults to read-only mode. Instead, we use
        # --dangerously-bypass-approvals-and-sandbox which:
        #   - Skips all confirmation prompts
        #   - Removes sandbox restrictions entirely
        #   - Allows direct file writes
        # This is safe for batch processing in git repositories where you have backups.
        $arguments += '--dangerously-bypass-approvals-and-sandbox'
    } else {
        Write-PSFMessage -Level Verbose -Message "Using auto-edit mode"
        $arguments += '--auto-edit'
    }

    if ($Model) {
        Write-PSFMessage -Level Verbose -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($ReasoningEffort) {
        Write-PSFMessage -Level Verbose -Message "Using reasoning effort: $ReasoningEffort"
        $arguments += '--config', "model_reasoning_effort=`"$ReasoningEffort`""
    }

    # Build the prompt FIRST (before image attachments)
    # IMPORTANT: The prompt must come before -i flags or Codex will read from stdin
    $promptToAdd = $null
    if ($TargetFile) {
        Write-PSFMessage -Level Verbose -Message "Target file: $TargetFile"

        # Extract just the filename for the prompt
        $fileName = Split-Path $TargetFile -Leaf

        # Codex exec needs explicit instruction to read and edit the file
        # The full prompt with context and instructions should already be in $Message
        $promptToAdd = if ($Message) {
            # Message already contains the full prompt with context and instructions
            # Just ensure the filename is clear
            "$Message`n`nEDIT AND SAVE: $fileName"
        } else {
            # Fallback if no message provided
            "Read, edit and save the file: $fileName"
        }

        Write-PSFMessage -Level Verbose -Message "Adding combined prompt with file reference"
    } elseif ($Message) {
        Write-PSFMessage -Level Verbose -Message "Adding prompt message (chat mode)"
        $promptToAdd = $Message
    }

    # Add the prompt to arguments if we have one
    if ($promptToAdd) {
        $arguments += $promptToAdd
    }

    # Add image attachments AFTER the prompt
    if ($Attachment) {
        foreach ($attachmentPath in $Attachment) {
            # Resolve to absolute path and normalize
            $resolvedPath = Resolve-Path -Path $attachmentPath -ErrorAction SilentlyContinue
            if ($resolvedPath) {
                $normalizedPath = $resolvedPath.Path -replace '\\', '/'
                Write-PSFMessage -Level Verbose -Message "Adding attachment: $normalizedPath"
                $arguments += '-i', $normalizedPath
            } else {
                Write-PSFMessage -Level Warning -Message "Could not resolve attachment path: $attachmentPath"
            }
        }
    }

    Write-PSFMessage -Level Verbose -Message "Codex arguments built: $($arguments -join ' ')"
    return $arguments
}
