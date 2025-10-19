function New-GeminiArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass
    )

    Write-PSFMessage -Level Verbose -Message "Building Gemini CLI arguments..."
    $arguments = @()

    # Note: YOLO mode auto-approves all actions, but we restrict to Read/Write/Edit tools only below,
    # so even in YOLO mode, Gemini cannot execute bash commands, run code, or perform other dangerous operations.
    # This provides reliability (no manual approvals) while maintaining safety (no execution capabilities).
    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Verbose -Message "Adding yolo mode flag (restricted to safe file operations only)"
        $arguments += '--yolo'
    } else {
        Write-PSFMessage -Level Verbose -Message "Using auto_edit approval mode"
        $arguments += '--approval-mode', 'auto_edit'
    }

    # Explicitly disable screen reader mode
    $arguments += '--screen-reader'
    $arguments += 'false'

    # SECURITY: Only allow file operations - no command execution, web search, or other tools
    # This ensures Gemini can only read, write, and edit files - nothing else
    Write-PSFMessage -Level Verbose -Message "Allowing only Read, Write, and Edit tools (no execution)"
    $arguments += '--allowed-tools', 'Read', 'Write', 'Edit'

    if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Verbose -Message "Adding debug flag"
        $arguments += '--debug'
    } elseif ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Verbose -Message "Adding verbose flag"
        $arguments += '-d'
    }

    if ($Model) {
        Write-PSFMessage -Level Verbose -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($TargetFile) {
        Write-PSFMessage -Level Verbose -Message "Target file: $TargetFile"

        # Extract parent directory to add to workspace for cross-repo access
        $targetDir = Split-Path (Split-Path $TargetFile -Parent) -Parent
        if ($targetDir -and (Test-Path $targetDir)) {
            Write-PSFMessage -Level Verbose -Message "Adding parent directory to workspace: $targetDir"
            $arguments += '--include-directories', $targetDir
        }

        $arguments += $TargetFile
    }

    Write-PSFMessage -Level Verbose -Message "Gemini arguments built: $($arguments -join ' ')"
    return $arguments
}
