function New-ClaudeArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    Write-PSFMessage -Level Verbose -Message "Building Claude Code arguments..."
    $arguments = @()

    if ($ReasoningEffort) {
        Write-PSFMessage -Level Verbose -Message "Reasoning effort will be applied via natural language trigger: $ReasoningEffort"
    }

    if ($UsePermissionBypass) {
        Write-PSFMessage -Level Verbose -Message "Adding permission bypass flag"
        $arguments += '--dangerously-skip-permissions'
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

    if ($TargetFile) {
        Write-PSFMessage -Level Verbose -Message "Target file: $TargetFile"
        $arguments += $TargetFile
    }

    Write-PSFMessage -Level Verbose -Message "Claude arguments built: $($arguments -join ' ')"
    return $arguments
}
