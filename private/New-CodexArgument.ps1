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
        Write-PSFMessage -Level Verbose -Message "Using full-auto mode"
        $arguments += '--full-auto'
        $arguments += '--sandbox', 'workspace-write'
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

    # Add image attachments if provided
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

    # Build the prompt to include the target file reference
    if ($TargetFile) {
        Write-PSFMessage -Level Verbose -Message "Target file: $TargetFile"

        # Extract just the filename for the prompt
        $fileName = Split-Path $TargetFile -Leaf

        # Combine the message with the file reference
        $fullMessage = if ($Message) {
            "$Message`n`nTarget file: $fileName"
        } else {
            $fileName
        }

        Write-PSFMessage -Level Verbose -Message "Adding combined prompt with file reference"
        $arguments += $fullMessage
    } elseif ($Message) {
        Write-PSFMessage -Level Verbose -Message "Adding prompt message (chat mode)"
        $arguments += $Message
    }

    Write-PSFMessage -Level Verbose -Message "Codex arguments built: $($arguments -join ' ')"
    return $arguments
}
