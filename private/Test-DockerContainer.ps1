function Test-DockerContainer {
    <#
    .SYNOPSIS
        Detects if running inside a Docker container.
    .DESCRIPTION
        Checks multiple indicators to reliably detect Docker/container environments:
        - /.dockerenv file (Docker)
        - /proc/1/cgroup contents (Docker, containerd, Kubernetes)
        - Environment variables (container runtimes)
    .EXAMPLE
        if (Test-DockerContainer) {
            Write-Host "Running in a container"
        }
    .OUTPUTS
        [bool] True if running in a container, False otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Check for /.dockerenv file (created by Docker)
    if (Test-Path '/.dockerenv') {
        Write-PSFMessage -Level Debug -Message "Docker detected via /.dockerenv"
        return $true
    }

    # Check cgroup for container indicators
    if (Test-Path '/proc/1/cgroup') {
        $cgroup = Get-Content '/proc/1/cgroup' -Raw -ErrorAction SilentlyContinue
        if ($cgroup -match 'docker|containerd|kubepods|lxc') {
            Write-PSFMessage -Level Debug -Message "Container detected via /proc/1/cgroup"
            return $true
        }
    }

    # Check for container-related environment variables
    if ($env:container -eq 'docker' -or $env:DOCKER_CONTAINER -or $env:KUBERNETES_SERVICE_HOST) {
        Write-PSFMessage -Level Debug -Message "Container detected via environment variable"
        return $true
    }

    return $false
}
