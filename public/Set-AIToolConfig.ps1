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
        The reasoning effort level for the model (Codex, Aider, Claude only). Valid values: low, medium, high

    .PARAMETER AiderOutputDir
        Directory for Aider output files (Aider only). Defaults to a temp directory that gets cleaned up.
        Set this to a custom path if you want to preserve Aider's history and metadata files.

    .PARAMETER IgnoreInstructions
        When enabled, the AI tool will ignore instruction files like CLAUDE.md, AGENTS.md, and other
        custom instruction files that are normally auto-loaded. This is useful when you want to run
        the tool without project-specific or user-specific instructions.

        For Claude: Uses an empty --system-prompt to bypass CLAUDE.md loading
        For Copilot: Uses --no-custom-instructions to bypass AGENTS.md loading
        For other tools: Behavior varies based on tool capabilities

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -EditMode Diff

    .EXAMPLE
        Set-AIToolConfig -Tool Claude -PermissionBypass

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -Model "gpt-4"

    .EXAMPLE
        Set-AIToolConfig -Tool Codex -ReasoningEffort high

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -AiderOutputDir "C:\MyAiderHistory"

    .EXAMPLE
        Set-AIToolConfig -Tool All -PermissionBypass
        Enables permission bypass for all AI tools.

    .EXAMPLE
        Set-AIToolConfig -Tool Claude -IgnoreInstructions
        Configures Claude to ignore CLAUDE.md and other instruction files.

    .EXAMPLE
        Set-AIToolConfig -Tool All -IgnoreInstructions
        Enables instruction bypass for all AI tools that support it.
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
        [string]$ReasoningEffort,
        [string]$AiderOutputDir,
        [switch]$IgnoreInstructions
    )

    # Handle "All" or "*" tool selection
    $toolsToConfig = @()
    if ($Tool -eq 'All' -or $Tool -eq '*') {
        Write-PSFMessage -Level Verbose -Message "Tool is '$Tool' - will configure all available tools"
        $toolsToConfig = $script:ToolDefinitions.Keys
        Write-PSFMessage -Level Verbose -Message "Tools to configure: $($toolsToConfig -join ', ')"
    } else {
        # Resolve tool alias to canonical name
        $resolvedTool = Resolve-ToolAlias -ToolName $Tool
        Write-PSFMessage -Level Verbose -Message "Resolved tool name: $resolvedTool"
        $toolsToConfig = @($resolvedTool)
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

        if ($PSBoundParameters.ContainsKey('IgnoreInstructions')) {
            Write-PSFMessage -Level Verbose -Message "IgnoreInstructions parameter provided: $($IgnoreInstructions.IsPresent)"
            Set-PSFConfig -FullName "AITools.$currentTool.IgnoreInstructions" -Value $IgnoreInstructions.IsPresent -PassThru | Register-PSFConfig
            Write-PSFMessage -Level Verbose -Message "Set $currentTool ignore instructions to: $($IgnoreInstructions.IsPresent)"
        }

        if ($AiderOutputDir) {
            Write-PSFMessage -Level Verbose -Message "AiderOutputDir parameter provided: $AiderOutputDir"
            if ($currentTool -ne 'Aider') {
                Write-PSFMessage -Level Warning -Message "AiderOutputDir is only applicable to Aider, skipping for $currentTool"
            } else {
                # Expand path and create directory if it doesn't exist
                $expandedPath = [System.IO.Path]::GetFullPath($AiderOutputDir)
                if (-not (Test-Path $expandedPath)) {
                    Write-PSFMessage -Level Verbose -Message "Creating output directory: $expandedPath"
                    New-Item -Path $expandedPath -ItemType Directory -Force | Out-Null
                }
                Set-PSFConfig -FullName "AITools.$currentTool.OutputDir" -Value $expandedPath -PassThru | Register-PSFConfig
                Write-PSFMessage -Level Verbose -Message "Set $currentTool output directory to: $expandedPath"
            }
        }

        Write-PSFMessage -Level Verbose -Message "Configuration saved to PSFramework for $currentTool"

        # Output the current configuration for the tool
        Get-PSFConfig -FullName "AITools.$currentTool.*" | Select-PSFObject -Property FullName, Value
    }
}
