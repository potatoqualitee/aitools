function New-CursorArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [string[]]$ContextFiles,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    Write-PSFMessage -Level Verbose -Message "Building Cursor arguments..."
    $arguments = @()

    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Verbose -Message "Adding auto-apply flag"
        $arguments += '--auto-apply'
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Verbose -Message "Adding verbose flag"
        $arguments += '--verbose'
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Verbose -Message "Adding debug flag"
        $arguments += '--debug'
    }

    if ($Model) {
        Write-PSFMessage -Level Verbose -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($ReasoningEffort) {
        Write-PSFMessage -Level Verbose -Message "Using reasoning effort: $ReasoningEffort"
        $arguments += '--reasoning-effort', $ReasoningEffort
    }

    # Add context files with --context-file flag
    if ($ContextFiles) {
        foreach ($ctxFile in $ContextFiles) {
            # Validate and resolve the context file path
            if (Test-Path $ctxFile) {
                # Resolve to full path
                $resolvedCtxFile = (Resolve-Path $ctxFile).Path
                Write-PSFMessage -Level Verbose -Message "Adding context file: $resolvedCtxFile (resolved from: $ctxFile)"
                $arguments += '--context-file', $resolvedCtxFile
            } else {
                Write-PSFMessage -Level Warning -Message "Context file path not found and will be skipped: $ctxFile"
            }
        }
    }

    if ($Message) {
        Write-PSFMessage -Level Verbose -Message "Adding message/prompt"
        $arguments += '--message', $Message
    }

    if ($TargetFile) {
        Write-PSFMessage -Level Verbose -Message "Target file: $TargetFile"
        $arguments += $TargetFile
    }

    Write-PSFMessage -Level Verbose -Message "Cursor arguments built: $($arguments -join ' ')"
    return $arguments
}
