function New-ClaudeArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [bool]$IgnoreInstructions,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    Write-PSFMessage -Level Verbose -Message "Building Claude Code arguments..."
    $arguments = @()

    if ($ReasoningEffort) {
        Write-PSFMessage -Level Verbose -Message "Reasoning effort will be applied via natural language trigger: $ReasoningEffort"
    }

    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Debug -Message "Adding permission bypass flag"
        $arguments += '--dangerously-skip-permissions'
    }

    if ($IgnoreInstructions) {
        Write-PSFMessage -Level Debug -Message "Adding minimal system prompt to bypass CLAUDE.md loading"
        $arguments += '--system-prompt', 'You are a helpful AI assistant. Complete the requested task.'
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Debug -Message "Adding verbose flag"
        $arguments += '--verbose'
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Debug -Message "Adding debug flag"
        $arguments += '--debug'
    }

    if ($Model) {
        Write-PSFMessage -Level Debug -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($TargetFile) {
        Write-PSFMessage -Level Debug -Message "Target file: $TargetFile"
        $arguments += $TargetFile
    }

    Write-PSFMessage -Level Verbose -Message "Claude arguments built: $($arguments -join ' ')"
    return $arguments
}
