function Resolve-ToolAlias {
    <#
    .SYNOPSIS
        Resolves a tool name or alias to the canonical tool name.

    .DESCRIPTION
        Maps user-friendly tool aliases (like "Code", "Copilot") to their canonical
        names (like "Claude", "Copilot") used in $script:ToolDefinitions.

    .PARAMETER ToolName
        The tool name or alias to resolve.

    .EXAMPLE
        Resolve-ToolAlias -ToolName "Code"
        Returns "Claude"

    .EXAMPLE
        Resolve-ToolAlias -ToolName "Copilot"
        Returns "Copilot"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName
    )

    # Return as-is if no alias mapping exists
    if (-not $script:ToolAliases) {
        return $ToolName
    }

    # Case-insensitive lookup for alias
    $alias = $script:ToolAliases.GetEnumerator() | Where-Object {
        $_.Key -eq $ToolName
    } | Select-Object -First 1

    if ($alias) {
        Write-PSFMessage -Level Verbose -Message "Resolved tool alias '$ToolName' to '$($alias.Value)'"
        return $alias.Value
    }

    # No alias found, return original name
    return $ToolName
}
