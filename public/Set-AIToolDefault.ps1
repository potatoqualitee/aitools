function Set-AIToolDefault {
    <#
    .SYNOPSIS
        Sets the default AI tool to use.

    .DESCRIPTION
        Configures which AI tool should be used by default when no -Tool parameter is specified.
        If the tool is not installed, it will prompt to install it.

    .PARAMETER Tool
        The AI tool to set as default.

    .PARAMETER AutoDetect
        Automatically detect and set the first available tool as default.

    .EXAMPLE
        Set-AIToolDefault -Tool Claude

    .EXAMPLE
        Set-AIToolDefault -AutoDetect
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Manual', Mandatory)]
        [string]$Tool,
        [Parameter(ParameterSetName = 'Auto')]
        [switch]$AutoDetect
    )

    if ($AutoDetect) {
        Write-PSFMessage -Level Verbose -Message "AutoDetect mode enabled, searching for available tools"
        $availableTool = Find-AvailableAITool
        if ($availableTool) {
            Write-PSFMessage -Level Verbose -Message "Found available tool: $availableTool"
            Set-PSFConfig -FullName 'AITools.DefaultTool' -Value $availableTool -PassThru | Register-PSFConfig
            Write-PSFMessage -Level Verbose -Message "Set default AI tool to: $availableTool"
        } else {
            Write-PSFMessage -Level Warning -Message "No AI tools detected. Please install a tool first using Install-AITool"
        }
    } else {
        Write-PSFMessage -Level Verbose -Message "Manual mode - setting default to: $Tool"

        # Resolve tool alias to canonical name
        $resolvedTool = Resolve-ToolAlias -ToolName $Tool
        Write-PSFMessage -Level Verbose -Message "Resolved tool name: $resolvedTool"

        $toolDef = $script:ToolDefinitions[$resolvedTool]

        # Check if tool definition exists (bail early if not, unless it's a custom tool)
        if (-not $toolDef) {
            Write-PSFMessage -Level Error -Message "Tool '$Tool' is not a recognized AI tool."
            Write-PSFMessage -Level Host -Message "Available tools: $($script:ToolDefinitions.Keys -join ', ')"
            return
        }

        Write-PSFMessage -Level Verbose -Message "Checking if $resolvedTool is installed"
        if (-not (Test-Command -Command $toolDef.Command)) {
            Write-PSFMessage -Level Warning -Message "$resolvedTool is not installed."
            $response = Read-Host "Would you like to install it now? (Y/N)"
            if ($response -eq 'Y' -or $response -eq 'y') {
                Write-PSFMessage -Level Verbose -Message "User chose to install $resolvedTool"
                Install-AITool -Name $resolvedTool
            } else {
                Write-PSFMessage -Level Verbose -Message "User declined installation"
                return
            }
        }

        Write-PSFMessage -Level Verbose -Message "Saving default tool configuration"
        Set-PSFConfig -FullName 'AITools.DefaultTool' -Value $resolvedTool -PassThru | Register-PSFConfig
        Write-PSFMessage -Level Verbose -Message "Set default AI tool to: $resolvedTool"
    }

    # Output the current configuration
    Get-PSFConfig -FullName 'AITools.DefaultTool' | Select-PSFObject -Property FullName, Value
}
