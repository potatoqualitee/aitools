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

    .PARAMETER RequirePermissions
        When set to $true, disables auto-approve mode and requires user confirmation for dangerous operations.
        When set to $false (default), enables permission bypass/auto-approve mode.

        This parameter accepts a boolean value, allowing you to explicitly set it to $true or $false:
        - Set-AIToolConfig -Tool Claude -RequirePermissions $true   # Requires permissions
        - Set-AIToolConfig -Tool Claude -RequirePermissions $false  # Auto-approve (default)

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

    .PARAMETER OAuthToken
        OAuth token for Claude authentication (Claude only). Accepts a SecureString for secure input.
        The token is stored in PSFramework configuration and automatically used when executing Claude.
        This enables headless/unattended execution without requiring the CLAUDE_CODE_OAUTH_TOKEN
        environment variable to be set manually.

        Note: If CLAUDE_CODE_OAUTH_TOKEN environment variable is set, it takes precedence over the
        stored token.

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -EditMode Diff

    .EXAMPLE
        Set-AIToolConfig -Tool Claude -RequirePermissions $true
        Disables auto-approve mode - Claude will prompt for confirmation on dangerous operations.

    .EXAMPLE
        Set-AIToolConfig -Tool Claude -RequirePermissions $false
        Enables auto-approve mode (default) - Claude will automatically approve all operations.

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -Model "gpt-4"

    .EXAMPLE
        Set-AIToolConfig -Tool Codex -ReasoningEffort high

    .EXAMPLE
        Set-AIToolConfig -Tool Aider -AiderOutputDir "C:\MyAiderHistory"

    .EXAMPLE
        Set-AIToolConfig -Tool All -RequirePermissions $false
        Enables auto-approve mode for all AI tools (the default behavior).

    .EXAMPLE
        Set-AIToolConfig -Tool Claude -IgnoreInstructions
        Configures Claude to ignore CLAUDE.md and other instruction files.

    .EXAMPLE
        Set-AIToolConfig -Tool All -IgnoreInstructions
        Enables instruction bypass for all AI tools that support it.

    .EXAMPLE
        Set-AIToolConfig -Tool Claude -OAuthToken (Read-Host -AsSecureString "Enter OAuth Token")
        Stores the OAuth token securely for Claude authentication.

    .EXAMPLE
        Set-AIToolConfig -Tool Claude -OAuthToken (ConvertTo-SecureString "sk-ant-oat-..." -AsPlainText -Force)
        Stores the OAuth token for headless/CI execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [ValidateSet('Diff', 'Whole')]
        [string]$EditMode,
        [Parameter()]
        [bool]$RequirePermissions,
        [string]$Model,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort,
        [string]$AiderOutputDir,
        [Alias('NoCustomInstructions')]
        [switch]$IgnoreInstructions,
        [Parameter()]
        [System.Security.SecureString]$OAuthToken
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

        if ($PSBoundParameters.ContainsKey('RequirePermissions')) {
            Write-PSFMessage -Level Verbose -Message "RequirePermissions parameter provided: $RequirePermissions"
            Set-PSFConfig -FullName "AITools.$currentTool.RequirePermissions" -Value $RequirePermissions -PassThru | Register-PSFConfig
            Write-PSFMessage -Level Verbose -Message "Set $currentTool require permissions to: $RequirePermissions"
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

        if ($PSBoundParameters.ContainsKey('OAuthToken')) {
            if ($currentTool -ne 'Claude') {
                Write-PSFMessage -Level Warning -Message "OAuthToken is only applicable to Claude, skipping for $currentTool"
            } else {
                # Convert SecureString to plain text for storage
                # PSFramework stores in user profile with restricted permissions
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($OAuthToken)
                $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

                Set-PSFConfig -FullName "AITools.$currentTool.OAuthToken" -Value $plainToken -PassThru | Register-PSFConfig
                Write-PSFMessage -Level Verbose -Message "Set $currentTool OAuth token"
            }
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
