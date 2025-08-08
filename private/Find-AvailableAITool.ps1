function Find-AvailableAITool {
    <#
    .SYNOPSIS
        Finds the first available AI tool based on priority order.

    .DESCRIPTION
        Checks for installed AI tools in order of priority (ClaudeCode, Codex, Gemini, GitHubCopilot, Aider)
        and returns the first one found.

    .OUTPUTS
        String - Name of the first available tool, or $null if none found
    #>
    [CmdletBinding()]
    param()

    Write-PSFMessage -Level Verbose -Message "Scanning for available AI tools..."

    # Sort tools by priority
    $sortedTools = $script:ToolDefinitions.GetEnumerator() |
        Sort-Object { $_.Value.Priority } |
        Select-Object -ExpandProperty Key

    foreach ($toolName in $sortedTools) {
        $tool = $script:ToolDefinitions[$toolName]
        Write-PSFMessage -Level Verbose -Message "Checking for $toolName ($($tool.Command))..."

        if (Test-Command -Command $tool.Command) {
            Write-PSFMessage -Level Verbose -Message "Found $toolName"
            return $toolName
        }
    }

    Write-PSFMessage -Level Verbose -Message "No AI tools found"
    return $null
}
