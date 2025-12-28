function Test-SudoRequired {
    <#
    .SYNOPSIS
        Determines if sudo is required for a command on the current platform.

    .DESCRIPTION
        Checks whether the current user needs sudo/elevated privileges to run
        system-level commands. On Linux, checks if running as root. On macOS,
        most operations (Homebrew, npm, pipx) do NOT require sudo.

    .PARAMETER Scope
        The installation scope. LocalMachine typically requires elevated privileges on Linux.

    .OUTPUTS
        [bool] True if sudo is required, False otherwise.

    .NOTES
        - Linux with LocalMachine scope: Requires sudo for apt-get and system-wide installations
        - macOS: Homebrew and most package managers do NOT require sudo
        - Windows: Not applicable (uses different elevation model)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope = 'CurrentUser'
    )

    $os = Get-OperatingSystem

    # Windows doesn't use sudo
    if ($os -eq 'Windows') {
        return $false
    }

    # macOS: Homebrew and modern package managers don't need sudo
    # They install to /usr/local or /opt/homebrew which are user-writable
    if ($os -eq 'MacOS') {
        return $false
    }

    # Linux: Only LocalMachine scope needs sudo
    if ($os -eq 'Linux') {
        if ($Scope -eq 'CurrentUser') {
            return $false
        }

        # LocalMachine scope - check if already root
        $userId = & id -u 2>$null
        if ($userId -eq '0') {
            # Already running as root
            return $false
        }

        # Need sudo for LocalMachine on Linux
        return $true
    }

    return $false
}
