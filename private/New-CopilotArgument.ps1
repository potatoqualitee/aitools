function New-CopilotArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [string]$WorkingDirectory
    )

    Write-PSFMessage -Level Verbose -Message "Building GitHub Copilot CLI arguments..."
    $arguments = @()

    # Always add --allow-all-tools for non-interactive mode
    Write-PSFMessage -Level Verbose -Message "Adding allow-all-tools flag"
    $arguments += '--allow-all-tools'

    # Add directory access first (must come before other flags for proper permission handling)
    if ($WorkingDirectory) {
        Write-PSFMessage -Level Verbose -Message "Adding working directory: $WorkingDirectory"
        $arguments += '--add-dir', $WorkingDirectory
    }

    if ($TargetFile) {
        $parentDir = Split-Path -Parent $TargetFile
        Write-PSFMessage -Level Verbose -Message "Adding directory: $parentDir"
        $arguments += '--add-dir', $parentDir

        if (-not (Test-Path $parentDir/.git)) {
            $grandparentDir = Split-Path -Parent $parentDir
            Write-PSFMessage -Level Verbose -Message "Adding directory: $grandparentDir"
            $arguments += '--add-dir', $grandparentDir
        }
    }

    if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) {
        Write-PSFMessage -Level Verbose -Message "Setting log level to debug"
        $arguments += '--log-level', 'debug'
    } elseif ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Verbose -Message "Setting log level to info"
        $arguments += '--log-level', 'info'
    }

    if ($Model) {
        Write-PSFMessage -Level Verbose -Message "Using model: $Model"
        $arguments += '--model', $Model
    }

    if ($Message) {
        Write-PSFMessage -Level Verbose -Message "Adding message prompt"
        $arguments += '-p', $Message
    }

    Write-PSFMessage -Level Verbose -Message "Copilot arguments built: $($arguments -join ' ')"
    return $arguments
}
