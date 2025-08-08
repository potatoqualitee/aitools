function Set-AIToolConfig {
    <#
    .SYNOPSIS
        Sets configuration for AI CLI tools.

    .DESCRIPTION
        Configures AI tool settings including edit modes and permission bypass mode.
        Uses PSFramework for persistent configuration.

    .PARAMETER Tool
        The AI tool to configure.

    .PARAMETER EditMode
        The edit mode to use (Aider only). Valid values: Diff, Whole

    .PARAMETER PermissionBypass
        Enable permission bypass/auto-approve mode for the tool.

    .PARAMETER Model
        Default model to use for the tool.

    .PARAMETER ReasoningEffort
        The reasoning effort level for the model (Codex, Aider, ClaudeCode only). Valid values: low, medium, high

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -EditMode Diff

    .EXAMPLE
        Set-AIToolConfig -Tool ClaudeCode -PermissionBypass

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -Model "gpt-4"

    .EXAMPLE
        Set-AIToolConfig -Tool Codex -ReasoningEffort high

    .EXAMPLE
        Set-AIToolConfig -Tool All -PermissionBypass
        Enables permission bypass for all AI tools.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [ValidateSet('Diff', 'Whole')]
        [string]$EditMode,
        [switch]$PermissionBypass,
        [string]$Model,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    # Handle "All" tool selection
    $toolsToConfig = @()
    if ($Tool -eq 'All') {
        Write-PSFMessage -Level Verbose -Message "Tool is 'All' - will configure all available tools"
        $toolsToConfig = $script:ToolDefinitions.Keys
        Write-PSFMessage -Level Verbose -Message "Tools to configure: $($toolsToConfig -join ', ')"
    } else {
        $toolsToConfig = @($Tool)
    }

    foreach ($currentTool in $toolsToConfig) {
        Write-PSFMessage -Level Verbose -Message "Configuring $currentTool"

        if ($EditMode) {
            Write-PSFMessage -Level Verbose -Message "EditMode parameter provided: $EditMode"
            if ($currentTool -ne 'Aider') {
                Write-PSFMessage -Level Warning -Message "EditMode is only applicable to Aider, skipping for $currentTool"
            } else {
                Write-PSFMessage -Level Verbose -Message "Setting edit mode for Aider"
                Set-PSFConfig -FullName "AITools.$currentTool.EditMode" -Value $EditMode -PassThru | Register-PSFConfig
                Write-PSFMessage -Level Verbose -Message "Set $currentTool edit mode to: $EditMode"
            }
        }

        if ($PSBoundParameters.ContainsKey('PermissionBypass')) {
            Write-PSFMessage -Level Verbose -Message "PermissionBypass parameter provided: $($PermissionBypass.IsPresent)"
            Set-PSFConfig -FullName "AITools.$currentTool.PermissionBypass" -Value $PermissionBypass.IsPresent -PassThru | Register-PSFConfig
            Write-PSFMessage -Level Verbose -Message "Set $currentTool permission bypass to: $($PermissionBypass.IsPresent)"
        }

        if ($Model) {
            Write-PSFMessage -Level Verbose -Message "Model parameter provided: $Model"
            Set-PSFConfig -FullName "AITools.$currentTool.Model" -Value $Model -PassThru | Register-PSFConfig
            Write-PSFMessage -Level Verbose -Message "Set $currentTool default model to: $Model"
        }

        if ($ReasoningEffort) {
            Write-PSFMessage -Level Verbose -Message "ReasoningEffort parameter provided: $ReasoningEffort"
            Set-PSFConfig -FullName "AITools.$currentTool.ReasoningEffort" -Value $ReasoningEffort -PassThru | Register-PSFConfig
            Write-PSFMessage -Level Verbose -Message "Set $currentTool reasoning effort to: $ReasoningEffort"
        }

        Write-PSFMessage -Level Verbose -Message "Configuration saved to PSFramework for $currentTool"

        # Output the current configuration for the tool
        Get-PSFConfig -FullName "AITools.$currentTool.*" | Select-PSFObject -Property FullName, Value
    }
}
