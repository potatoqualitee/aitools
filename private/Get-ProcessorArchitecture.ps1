function Get-ProcessorArchitecture {
    <#
    .SYNOPSIS
        Detects the processor architecture of the current system.

    .DESCRIPTION
        Returns the processor architecture normalized for use in download URLs and binary selection.
        Supports Windows, Linux, and macOS on both Intel/AMD (amd64) and ARM (arm64) processors.

    .OUTPUTS
        String - One of: 'amd64', 'arm64'

    .EXAMPLE
        Get-ProcessorArchitecture
        Returns 'amd64' on Intel/AMD systems or 'arm64' on ARM-based systems.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Write-PSFMessage -Level Verbose -Message "Detecting processor architecture..."

    $os = Get-OperatingSystem
    $arch = $null

    if ($os -eq 'Windows') {
        # On Windows, check PROCESSOR_ARCHITECTURE environment variable
        $processorArch = $env:PROCESSOR_ARCHITECTURE
        Write-PSFMessage -Level Verbose -Message "Windows PROCESSOR_ARCHITECTURE: $processorArch"

        switch ($processorArch) {
            'AMD64' { $arch = 'amd64' }
            'ARM64' { $arch = 'arm64' }
            'x86' {
                # Check if running 32-bit PowerShell on 64-bit Windows
                if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
                    $arch = 'amd64'
                } elseif ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
                    $arch = 'arm64'
                } else {
                    # True 32-bit system - fall back to amd64 and hope for the best
                    Write-PSFMessage -Level Warning -Message "32-bit system detected. Using amd64 binary which may not work."
                    $arch = 'amd64'
                }
            }
            default {
                Write-PSFMessage -Level Warning -Message "Unknown Windows architecture: $processorArch. Defaulting to amd64."
                $arch = 'amd64'
            }
        }
    } elseif ($os -eq 'MacOS') {
        # On macOS, use uname -m
        try {
            $unameResult = & uname -m 2>&1 | Out-String
            $unameResult = $unameResult.Trim()
            Write-PSFMessage -Level Verbose -Message "macOS uname -m: $unameResult"

            switch ($unameResult) {
                'x86_64' { $arch = 'amd64' }
                'arm64' { $arch = 'arm64' }
                'aarch64' { $arch = 'arm64' }
                default {
                    Write-PSFMessage -Level Warning -Message "Unknown macOS architecture: $unameResult. Defaulting to amd64."
                    $arch = 'amd64'
                }
            }
        } catch {
            Write-PSFMessage -Level Warning -Message "Failed to detect macOS architecture: $_. Defaulting to amd64."
            $arch = 'amd64'
        }
    } elseif ($os -eq 'Linux') {
        # On Linux, use uname -m
        try {
            $unameResult = & uname -m 2>&1 | Out-String
            $unameResult = $unameResult.Trim()
            Write-PSFMessage -Level Verbose -Message "Linux uname -m: $unameResult"

            switch ($unameResult) {
                'x86_64' { $arch = 'amd64' }
                'amd64' { $arch = 'amd64' }
                'arm64' { $arch = 'arm64' }
                'aarch64' { $arch = 'arm64' }
                default {
                    Write-PSFMessage -Level Warning -Message "Unknown Linux architecture: $unameResult. Defaulting to amd64."
                    $arch = 'amd64'
                }
            }
        } catch {
            Write-PSFMessage -Level Warning -Message "Failed to detect Linux architecture: $_. Defaulting to amd64."
            $arch = 'amd64'
        }
    } else {
        Write-PSFMessage -Level Warning -Message "Unknown OS. Defaulting to amd64 architecture."
        $arch = 'amd64'
    }

    Write-PSFMessage -Level Verbose -Message "Detected architecture: $arch"
    return $arch
}
