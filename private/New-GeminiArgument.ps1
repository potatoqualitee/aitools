function New-GeminiArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [switch]$UseStreaming
    )

    Write-PSFMessage -Level Verbose -Message "Building Gemini CLI arguments..."
    $arguments = @()

    # Note: YOLO mode auto-approves all actions, but we restrict to Read/Write/Edit tools only below,
    # so even in YOLO mode, Gemini cannot execute bash commands, run code, or perform other dangerous operations.
    # This provides reliability (no manual approvals) while maintaining safety (no execution capabilities).
    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Debug -Message "Adding yolo mode flag (restricted to safe file operations only)"
        $arguments += '--yolo'
    } else {
        Write-PSFMessage -Level Debug -Message "Using auto_edit approval mode"
        $arguments += '--approval-mode', 'auto_edit'
    }

    # Explicitly disable screen reader mode
    $arguments += '--screen-reader'
    $arguments += 'false'

    if ($UseStreaming) {
        Write-PSFMessage -Level Debug -Message "Adding streaming output format flag"
        $arguments += '--output-format', 'stream-json'
    }

    # SECURITY: Only allow file operations - no command execution, web search, or other tools
    # This ensures Gemini can only read, write, and edit files - nothing else
    Write-PSFMessage -Level Debug -Message "Allowing only Read, Write, and Edit tools (no execution)"
    $arguments += '--allowed-tools', 'Read', 'Write', 'Edit'

    if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Debug -Message "Adding debug flag"
        $arguments += '--debug'
    } elseif ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Debug -Message "Adding verbose flag"
        $arguments += '-d'
    }

    if ($Model) {
        Write-PSFMessage -Level Debug -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($TargetFile) {
        # Validate and resolve the target file path
        if (Test-Path $TargetFile) {
            $resolvedTargetFile = (Resolve-Path $TargetFile).Path
            Write-PSFMessage -Level Debug -Message "Target file: $resolvedTargetFile (resolved from: $TargetFile)"

            # Extract parent directory to add to workspace for cross-repo access
            $targetDir = Split-Path (Split-Path $resolvedTargetFile -Parent) -Parent
            if ($targetDir -and (Test-Path $targetDir)) {
                Write-PSFMessage -Level Debug -Message "Adding parent directory to workspace: $targetDir"
                $arguments += '--include-directories', $targetDir
            }

            $arguments += $resolvedTargetFile
        } else {
            Write-PSFMessage -Level Warning -Message "Target file path not found: $TargetFile"
            # Still add the path - let Gemini handle the error
            $arguments += $TargetFile
        }
    }

    Write-PSFMessage -Level Verbose -Message "Gemini arguments built: $($arguments -join ' ')"
    return $arguments
}
