function Initialize-AIToolDefault {
    <#
    .SYNOPSIS
        Initializes the default AI tool configuration.

    .DESCRIPTION
        Checks if a default tool is configured. If not, scans for available tools
        and prompts user to install one if none are found.
    #>
    [CmdletBinding()]
    param()

    $defaultTool = Get-PSFConfigValue -FullName 'AITools.DefaultTool' -Fallback $null

    if ($defaultTool) {
        Write-PSFMessage -Level Verbose -Message "Default tool already configured: $defaultTool"
        return
    }

    Write-PSFMessage -Level Verbose -Message "No default tool configured, scanning for available tools..."

    $availableTool = Find-AvailableAITool

    if ($availableTool) {
        Set-PSFConfig -FullName 'AITools.DefaultTool' -Value $availableTool -PassThru | Register-PSFConfig
        Write-PSFMessage -Level Verbose -Message "Detected and set default AI tool: $availableTool"
    } else {
        Write-PSFMessage -Level Verbose -Message "`nNo AI tools detected. Please install one of the following:`n"

        $sortedTools = $script:ToolDefinitions.GetEnumerator() |
            Sort-Object { $_.Value.Priority }

        $index = 1
        foreach ($tool in $sortedTools) {
            $note = if ($tool.Value.Note) { " - $($tool.Value.Note)" } else { "" }
            Write-PSFMessage -Level Verbose -Message "$index. $($tool.Key)$note"
            $index++
        }

        Write-PSFMessage -Level Verbose -Message "`nTo install a tool, run: Install-AITool -Name <ToolName>"
        Write-PSFMessage -Level Verbose -Message "Example: Install-AITool -Name Claude"
    }
}
