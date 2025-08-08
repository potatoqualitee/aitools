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
    Write-PSFMessage -Level Verbose -Message "Message: $Message"

    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Verbose -Message "Adding permission bypass flag"
        $arguments += '--yes-always'
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Verbose'] -or $PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Verbose -Message "Adding verbose flag"
        $arguments += '--verbose'
    }

    if ($Model) {
        Write-PSFMessage -Level Verbose -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($ReasoningEffort) {
        Write-PSFMessage -Level Verbose -Message "Using reasoning effort: $ReasoningEffort"
        $arguments += '--reasoning-effort', $ReasoningEffort
    }

    if ($EditMode) {
        Write-PSFMessage -Level Verbose -Message "Edit mode: $EditMode"
        $editFlag = $script:ToolDefinitions['Aider'].EditModeMap[$EditMode]
        if ($editFlag) {
            $arguments += $editFlag  # Add array elements (flag and value)
        }
    }

    Write-PSFMessage -Level Verbose -Message "Adding no-auto-commits, cache-prompts, and no-pretty flags"
    $arguments += '--no-auto-commits'
    $arguments += '--cache-prompts'
    $arguments += '--no-pretty'

    if ($TargetFile) {
        Write-PSFMessage -Level Verbose -Message "Target file: $TargetFile"
        $arguments += '--file', $TargetFile
    }

    if ($ContextFiles) {
        Write-PSFMessage -Level Verbose -Message "Adding $($ContextFiles.Count) context file(s)"
        foreach ($ctx in $ContextFiles) {
            Write-PSFMessage -Level Verbose -Message "Context file: $ctx"
            $arguments += '--read', $ctx
        }
    }

    Write-PSFMessage -Level Verbose -Message "Aider arguments built: $($arguments -join ' ')"
    return $arguments
}
