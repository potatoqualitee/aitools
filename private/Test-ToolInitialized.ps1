function Test-ToolInitialized {
    <#
    .SYNOPSIS
        Checks if an AI tool is initialized and ready to use.

    .DESCRIPTION
        Checks if a tool is installed and properly initialized with credentials.

    .PARAMETER Tool
        The name of the tool to check.

    .OUTPUTS
        Boolean - True if tool is initialized, False otherwise
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool
    )

    $toolName = $script:ToolDefinitions[$Tool]

    if (-not (Test-Command -Command $toolName.Command)) {
        Write-PSFMessage -Level Verbose -Message "$Tool is not installed"
        return $false
    }

    # Check if tool needs initialization
    if ($toolName.InitCommand -eq 'API_KEY_CHECK') {
        # Special case for Aider - check API keys
        return Test-AiderAPIKey
    }

    # For other tools, assume they're ready if installed
    # Could add more sophisticated checks here in the future
    return $true
}
