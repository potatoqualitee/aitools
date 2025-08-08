function Get-AIToolConfig {
    <#
    .SYNOPSIS
        Retrieves configuration for AI CLI tools.

    .DESCRIPTION
        Displays the current configuration for the specified AI tool.

    .PARAMETER Tool
        The AI tool whose configuration should be retrieved. If not specified, shows default tool and all configurations.

    .EXAMPLE
        Get-AIToolConfig -Tool Aider

    .EXAMPLE
        Get-AIToolConfig
        Shows the default tool and all tool configurations
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tool
    )

    if ($Tool) {
        if ($Tool -eq 'All') {
            Write-PSFMessage -Level Verbose -Message "Tool is 'All' - retrieving configuration for all tools"
            Get-PSFConfig -FullName "AITools.*"
        } else {
            Get-PSFConfig -FullName "AITools.$Tool.*"
        }
    } else {
        $defaultTool = Get-PSFConfigValue -FullName 'AITools.DefaultTool' -Fallback $null
        if ($defaultTool) {
            Write-PSFMessage -Level Verbose -Message "Default Tool: $defaultTool"
        } else {
            Write-PSFMessage -Level Verbose -Message "Default Tool: Not configured"
        }
        Write-PSFMessage -Level Verbose -Message ""
        Get-PSFConfig -FullName "AITools.*"
    }
}
