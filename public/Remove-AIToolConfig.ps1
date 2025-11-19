function Remove-AIToolConfig {
    <#
    .SYNOPSIS
        Removes specific configuration settings for AI CLI tools.

    .DESCRIPTION
        Removes individual configuration settings for AI tools. Unlike Clear-AIToolConfig which removes
        all configurations for a tool, this function allows you to remove specific settings like EditMode,
        PermissionBypass, Model, or ReasoningEffort. Supports pipeline input for batch operations.

    .PARAMETER Tool
        The AI tool whose configuration should be modified.

    .PARAMETER EditMode
        Remove the EditMode configuration setting.

    .PARAMETER PermissionBypass
        Remove the PermissionBypass configuration setting.

    .PARAMETER Model
        Remove the Model configuration setting.

    .PARAMETER ReasoningEffort
        Remove the ReasoningEffort configuration setting.

    .PARAMETER All
        Remove all configuration settings for the specified tool (equivalent to Clear-AIToolConfig).

    .EXAMPLE
        Remove-AIToolConfig -Tool Aider -EditMode
        Removes the EditMode configuration for Aider.

    .EXAMPLE
        Remove-AIToolConfig -Tool Claude -Model
        Removes the Model configuration for Claude.

    .EXAMPLE
        Get-AIToolConfig -Tool Aider | Remove-AIToolConfig -EditMode
        Uses pipeline to remove EditMode configuration from Aider.

    .EXAMPLE
        'Aider', 'Claude' | Remove-AIToolConfig -PermissionBypass
        Removes PermissionBypass configuration from multiple tools via pipeline.

    .EXAMPLE
        Remove-AIToolConfig -Tool Codex -All
        Removes all configuration settings for Codex.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Tool,
        [switch]$EditMode,
        [switch]$PermissionBypass,
        [switch]$Model,
        [switch]$ReasoningEffort,
        [switch]$All
    )

    process {
        # Extract tool name if pipeline input is from Get-AIToolConfig
        if ($Tool -match 'AITools\.([^.]+)\.') {
            $toolName = $Matches[1]
            Write-PSFMessage -Level Verbose -Message "Extracted tool name from pipeline: $toolName"
        } else {
            $toolName = $Tool
        }

        Write-PSFMessage -Level Verbose -Message "Processing configuration removal for $toolName"

        # If -All is specified, clear all configurations for this tool
        if ($All) {
            if ($PSCmdlet.ShouldProcess($toolName, "Remove all configuration settings")) {
                $configs = Get-PSFConfig -FullName "AITools.$toolName.*"
                foreach ($config in $configs) {
                    Unregister-PSFConfig -FullName $config.FullName
                    Write-PSFMessage -Level Verbose -Message "Removed: $($config.FullName)"
                }
                Write-PSFMessage -Level Host -Message "Removed all configuration settings for $toolName"
            }
            return
        }

        # Track if any settings were specified
        $settingsRemoved = $false

        # Remove specific settings
        if ($EditMode) {
            $configName = "AITools.$toolName.EditMode"
            if ($PSCmdlet.ShouldProcess($configName, "Remove configuration")) {
                $config = Get-PSFConfig -FullName $configName
                if ($config) {
                    Unregister-PSFConfig -FullName $configName
                    Write-PSFMessage -Level Verbose -Message "Removed EditMode configuration for $toolName"
                    $settingsRemoved = $true
                } else {
                    Write-PSFMessage -Level Warning -Message "EditMode configuration not found for $toolName"
                }
            }
        }

        if ($PermissionBypass) {
            $configName = "AITools.$toolName.PermissionBypass"
            if ($PSCmdlet.ShouldProcess($configName, "Remove configuration")) {
                $config = Get-PSFConfig -FullName $configName
                if ($config) {
                    Unregister-PSFConfig -FullName $configName
                    Write-PSFMessage -Level Verbose -Message "Removed PermissionBypass configuration for $toolName"
                    $settingsRemoved = $true
                } else {
                    Write-PSFMessage -Level Warning -Message "PermissionBypass configuration not found for $toolName"
                }
            }
        }

        if ($Model) {
            $configName = "AITools.$toolName.Model"
            if ($PSCmdlet.ShouldProcess($configName, "Remove configuration")) {
                $config = Get-PSFConfig -FullName $configName
                if ($config) {
                    Unregister-PSFConfig -FullName $configName
                    Write-PSFMessage -Level Verbose -Message "Removed Model configuration for $toolName"
                    $settingsRemoved = $true
                } else {
                    Write-PSFMessage -Level Warning -Message "Model configuration not found for $toolName"
                }
            }
        }

        if ($ReasoningEffort) {
            $configName = "AITools.$toolName.ReasoningEffort"
            if ($PSCmdlet.ShouldProcess($configName, "Remove configuration")) {
                $config = Get-PSFConfig -FullName $configName
                if ($config) {
                    Unregister-PSFConfig -FullName $configName
                    Write-PSFMessage -Level Verbose -Message "Removed ReasoningEffort configuration for $toolName"
                    $settingsRemoved = $true
                } else {
                    Write-PSFMessage -Level Warning -Message "ReasoningEffort configuration not found for $toolName"
                }
            }
        }

        # If no specific settings were specified, show warning
        if (-not $settingsRemoved -and -not $All) {
            Write-PSFMessage -Level Warning -Message "No configuration settings specified for removal. Use -EditMode, -PermissionBypass, -Model, -ReasoningEffort, or -All"
        } elseif ($settingsRemoved) {
            Write-PSFMessage -Level Host -Message "Configuration settings removed for $toolName"
        }
    }
}
