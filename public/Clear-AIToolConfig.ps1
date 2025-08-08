function Clear-AIToolConfig {
    <#
    .SYNOPSIS
        Clears all AI tool configurations.

    .DESCRIPTION
        Removes all stored configurations for AI tools including the default tool setting.
        To clear a specific tool only, use the -Tool parameter.

    .PARAMETER Tool
        Optional. Specify a specific AI tool whose configuration should be cleared.
        If not specified, clears ALL AI tool configurations.

    .EXAMPLE
        Clear-AIToolConfig
        Clears all AI tool configurations (default behavior).

    .EXAMPLE
        Clear-AIToolConfig -Tool Aider
        Clears configuration only for the Aider tool.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$Tool
    )

    if ($Tool -and $Tool -ne 'All') {
        # Clear specific tool configuration
        if ($PSCmdlet.ShouldProcess($Tool, "Clear configuration")) {
            $configs = Get-PSFConfig -FullName "AITools.$Tool.*"
            foreach ($config in $configs) {
                Unregister-PSFConfig -FullName $config.FullName
            }
            Write-PSFMessage -Level Verbose -Message "Cleared configuration for $Tool"
        }
    } else {
        # Clear ALL configurations (either no Tool specified or Tool -eq 'All')
        if ($PSCmdlet.ShouldProcess("All AI tool configurations", "Clear configuration")) {
            $configs = Get-PSFConfig -FullName "AITools.*"
            if ($configs) {
                foreach ($config in $configs) {
                    Unregister-PSFConfig -FullName $config.FullName
                }
                Write-PSFMessage -Level Verbose -Message "Cleared all AI tool configurations"
            } else {
                Write-PSFMessage -Level Verbose -Message "No AI tool configurations found"
            }
        }
    }
}
