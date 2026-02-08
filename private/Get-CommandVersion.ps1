function Get-CommandVersion {
    <#
    .SYNOPSIS
        Gets the version output of a CLI command using process-based execution.

    .DESCRIPTION
        Runs '<command> --version' using System.Diagnostics.Process with stdin redirected
        and immediately closed. This prevents CLIs (like Claude Code) from detecting piped
        stdin and switching to pipe/print mode, which causes errors when using PowerShell's
        & operator with 2>&1 redirection.

    .PARAMETER Command
        The command name to get the version for.

    .OUTPUTS
        System.String - The first non-empty line of version output, or $null on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    # Prefer Application type (actual exe) over Functions/Aliases that install scripts may create
    $cmd = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) {
        $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    }
    if ($null -eq $cmd) {
        return $null
    }

    $exePath = $cmd.Source
    if ([string]::IsNullOrWhiteSpace($exePath)) {
        return $null
    }

    $process = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true

        # .cmd/.bat files on Windows must run via cmd.exe
        $extension = [System.IO.Path]::GetExtension($exePath).ToLowerInvariant()
        if ($extension -in '.cmd', '.bat') {
            $psi.FileName = 'cmd.exe'
            $psi.Arguments = "/c `"$exePath`" --version"
        } else {
            $psi.FileName = $exePath
            $psi.Arguments = '--version'
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null

        # Close stdin immediately to prevent interactive prompts
        $process.StandardInput.Close()

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()

        if (-not $process.WaitForExit(10000)) {
            try { $process.Kill() } catch { }
            return $null
        }

        # Check stdout first, fall back to stderr (some CLIs output version to stderr)
        $result = ($stdout -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($result)) {
            $result = ($stderr -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        }

        if ([string]::IsNullOrWhiteSpace($result)) {
            return $null
        }

        return $result
    } catch {
        return $null
    } finally {
        if ($null -ne $process) {
            try { $process.Dispose() } catch { }
        }
    }
}
