function Show-ModuleMessage {
    <#
    .SYNOPSIS
        Displays a message from a text file in the messages directory.

    .DESCRIPTION
        Loads and displays message content from text files stored in the module's messages directory.
        Outputs each line using Write-PSFMessage with the specified level.

    .PARAMETER MessageName
        The name of the message file (without .txt extension) to display.

    .PARAMETER Level
        The PSFramework message level to use. Default is 'Output'.

    .EXAMPLE
        Show-ModuleMessage -MessageName 'aider-api-key-info'
        Displays the Aider API key configuration information.

    .EXAMPLE
        Show-ModuleMessage -MessageName 'claudecode-init-prompt' -Level 'Host'
        Displays the Claude Code initialization prompt using Host level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MessageName,

        [Parameter()]
        [string]$Level = 'Output'
    )

    $messagePath = Join-PSFPath -Path $script:ModuleRoot -Child "messages", "$MessageName.txt"

    if (-not (Test-Path $messagePath)) {
        Write-PSFMessage -Level Warning -Message "Message file not found: $messagePath"
        return
    }

    Write-PSFMessage -Level $Level -Message (Get-Content -Path $messagePath -Raw)
}
