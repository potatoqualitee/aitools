function Get-ToolConfiguration {
    <#
    .SYNOPSIS
        Loads tool-specific configuration from PSFramework config.

    .DESCRIPTION
        Retrieves configuration settings for a specific AI tool, including model,
        permission bypass, edit mode, reasoning effort, and ignore instructions settings.
        Command-line overrides take precedence over configured defaults.

    .PARAMETER ToolName
        The name of the AI tool (e.g., Claude, Aider, Codex).

    .PARAMETER ModelOverride
        Optional model override from command line. Takes precedence over configured default.

    .PARAMETER ReasoningEffortOverride
        Optional reasoning effort override from command line. Takes precedence over configured default.

    .PARAMETER IgnoreInstructionsOverride
        Optional switch to override ignore instructions setting. When specified, takes precedence
        over configured default.

    .PARAMETER IgnoreInstructionsBound
        Indicates whether the IgnoreInstructions parameter was explicitly bound (from $PSBoundParameters).

    .OUTPUTS
        [hashtable] with keys:
        - RequirePermissions: Whether to require user confirmation for dangerous operations (false = auto-approve)
        - Model: The model to use (override or configured default)
        - EditMode: The edit mode (Diff, etc.)
        - ReasoningEffort: The reasoning effort level (low, medium, high)
        - IgnoreInstructions: Whether to ignore instruction files

    .EXAMPLE
        $config = Get-ToolConfiguration -ToolName 'Claude' -ModelOverride 'claude-3-opus'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter()]
        [string]$ModelOverride,

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', '')]
        [string]$ReasoningEffortOverride,

        [Parameter()]
        [switch]$IgnoreInstructionsOverride,

        [Parameter()]
        [bool]$IgnoreInstructionsBound = $false,

        [Parameter()]
        [bool]$RequirePermissionsOverride,

        [Parameter()]
        [bool]$RequirePermissionsBound = $false
    )

    # Load configuration for the tool
    # RequirePermissions: $false (default) = auto-approve, $true = require confirmation
    $configuredRequirePermissions = Get-PSFConfigValue -FullName "AITools.$ToolName.RequirePermissions" -Fallback $false
    Write-PSFMessage -Level Verbose -Message "Configured require permissions: $configuredRequirePermissions"

    $configuredModel = Get-PSFConfigValue -FullName "AITools.$ToolName.Model" -Fallback $null
    Write-PSFMessage -Level Verbose -Message "Configured model: $configuredModel"

    $editMode = Get-PSFConfigValue -FullName "AITools.$ToolName.EditMode" -Fallback 'Diff'
    Write-PSFMessage -Level Verbose -Message "Edit mode: $editMode"

    $configuredReasoningEffort = Get-PSFConfigValue -FullName "AITools.$ToolName.ReasoningEffort" -Fallback $null
    Write-PSFMessage -Level Verbose -Message "Configured reasoning effort: $configuredReasoningEffort"

    $configuredIgnoreInstructions = Get-PSFConfigValue -FullName "AITools.$ToolName.IgnoreInstructions" -Fallback $false
    Write-PSFMessage -Level Verbose -Message "Configured ignore instructions: $configuredIgnoreInstructions"

    # Apply overrides
    $modelToUse = if ($ModelOverride) { $ModelOverride } else { $configuredModel }
    Write-PSFMessage -Level Verbose -Message "Model to use: $modelToUse"

    $reasoningEffortToUse = if ($ReasoningEffortOverride) { $ReasoningEffortOverride } else { $configuredReasoningEffort }
    Write-PSFMessage -Level Verbose -Message "Reasoning effort to use: $reasoningEffortToUse"

    # Command-line parameter overrides config (if switch is present, use it; otherwise use config)
    $ignoreInstructionsToUse = if ($IgnoreInstructionsBound) { $IgnoreInstructionsOverride.IsPresent } else { $configuredIgnoreInstructions }
    Write-PSFMessage -Level Verbose -Message "Ignore instructions to use: $ignoreInstructionsToUse"

    # Command-line parameter overrides config for RequirePermissions
    $requirePermissionsToUse = if ($RequirePermissionsBound) { $RequirePermissionsOverride } else { $configuredRequirePermissions }
    Write-PSFMessage -Level Verbose -Message "Require permissions to use: $requirePermissionsToUse"

    return @{
        RequirePermissions = $requirePermissionsToUse
        Model              = $modelToUse
        EditMode           = $editMode
        ReasoningEffort    = $reasoningEffortToUse
        IgnoreInstructions = $ignoreInstructionsToUse
    }
}
