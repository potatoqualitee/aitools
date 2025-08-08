function Get-OperatingSystem {
    Write-PSFMessage -Level Verbose -Message "Detecting operating system..."
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($IsWindows) {
            Write-PSFMessage -Level Verbose -Message "Detected OS: Windows"
            return 'Windows'
        }
        if ($IsLinux) {
            Write-PSFMessage -Level Verbose -Message "Detected OS: Linux"
            return 'Linux'
        }
        if ($IsMacOS) {
            Write-PSFMessage -Level Verbose -Message "Detected OS: MacOS"
            return 'MacOS'
        }
    } else {
        Write-PSFMessage -Level Verbose -Message "Detected OS: Windows (PowerShell < 6)"
        return 'Windows'
    }
}
