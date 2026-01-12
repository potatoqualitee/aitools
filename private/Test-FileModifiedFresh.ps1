function Test-FileModifiedFresh {
    <#
    .SYNOPSIS
        Performs a fresh check to determine if a file has been modified.

    .DESCRIPTION
        Checks if a specific file has uncommitted or staged changes in git.
        This is the "Stage 2" verification performed right before processing,
        catching files modified by concurrent processes or previous file processing.

    .PARAMETER FilePath
        The file path to check.

    .PARAMETER RepoRoot
        The git repository root path.

    .OUTPUTS
        [bool] $true if the file is modified (should be skipped), $false otherwise.

    .EXAMPLE
        if (Test-FileModifiedFresh -FilePath "script.ps1" -RepoRoot "C:\repo") {
            Write-Host "File has been modified, skipping"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    Write-PSFMessage -Level Verbose -Message "Fresh check before processing: $FilePath"

    $isModified = $false

    try {
        # Normalize both paths to forward slashes for comparison
        $normalizedFile = $FilePath -replace '\\', '/'
        $normalizedRepoRoot = $RepoRoot -replace '\\', '/'
        $escapedRepoRoot = [regex]::Escape($normalizedRepoRoot)

        # Remove repo root prefix and leading slash to get relative path
        $relativePath = $normalizedFile -replace "^$escapedRepoRoot", '' -replace '^/', ''

        # Check uncommitted changes for this specific file
        $workingTreeCheck = git diff --name-only -- $relativePath 2>&1
        if ($LASTEXITCODE -eq 0 -and $workingTreeCheck) {
            Write-PSFMessage -Level Verbose -Message "File has uncommitted changes: $FilePath"
            $isModified = $true
        }

        # Check staged changes for this specific file
        if (-not $isModified) {
            $stagedCheck = git diff --name-only --cached -- $relativePath 2>&1
            if ($LASTEXITCODE -eq 0 -and $stagedCheck) {
                Write-PSFMessage -Level Verbose -Message "File has staged changes: $FilePath"
                $isModified = $true
            }
        }
    } catch {
        Write-PSFMessage -Level Warning -Message "Error during fresh check: $_. Skipping file to be safe."
        $isModified = $true
    }

    return $isModified
}
