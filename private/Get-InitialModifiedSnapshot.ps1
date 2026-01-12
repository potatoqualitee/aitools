function Get-InitialModifiedSnapshot {
    <#
    .SYNOPSIS
        Builds a hashtable of modified files for O(1) lookup during -SkipModified processing.

    .DESCRIPTION
        Performs an initial sweep of all modified files in the repository and returns
        a hashtable with normalized paths as keys for fast lookup. This includes:
        - Uncommitted working tree changes
        - Staged changes
        - Committed but not pushed changes (for feature branches)
        - Recent commit changes (for main branch, based on CommitDepth)

    .PARAMETER GitContext
        The git context hashtable from Initialize-GitContext containing UpstreamBranch,
        IsOnMainBranch, CommitDepth, CurrentBranch, and RepoRoot.

    .OUTPUTS
        [hashtable] with normalized file paths (forward slashes) as keys and $true as values.
        Empty hashtable if no modified files found.

    .EXAMPLE
        $gitContext = Initialize-GitContext -CommitDepth 5
        $snapshot = Get-InitialModifiedSnapshot -GitContext $gitContext
        if ($snapshot.ContainsKey($normalizedPath)) {
            Write-Host "File is modified"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$GitContext
    )

    $snapshot = @{}

    if (-not $GitContext -or -not $GitContext.RepoRoot) {
        Write-PSFMessage -Level Verbose -Message "No valid git context provided, returning empty snapshot"
        return $snapshot
    }

    Write-PSFMessage -Level Verbose -Message "Performing initial sweep of modified files..."
    $allModifiedFiles = @()

    # Get uncommitted working tree changes
    $workingTreeChanges = git diff --name-only 2>&1 | Where-Object { $_ -is [string] }
    if ($LASTEXITCODE -eq 0 -and $workingTreeChanges) {
        $allModifiedFiles += $workingTreeChanges
        Write-PSFMessage -Level Verbose -Message "Found $(@($workingTreeChanges).Count) uncommitted working tree change(s)"
    }

    # Get staged changes
    $stagedChanges = git diff --name-only --cached 2>&1 | Where-Object { $_ -is [string] }
    if ($LASTEXITCODE -eq 0 -and $stagedChanges) {
        $allModifiedFiles += $stagedChanges
        Write-PSFMessage -Level Verbose -Message "Found $(@($stagedChanges).Count) staged change(s)"
    }

    # Get committed changes based on branch
    if ($GitContext.IsOnMainBranch) {
        $recentCommitChanges = git log -n $GitContext.CommitDepth --name-only --pretty=format: 2>&1 | Where-Object { $_ -is [string] -and $_.Trim() }
        if ($LASTEXITCODE -eq 0 -and $recentCommitChanges) {
            $allModifiedFiles += $recentCommitChanges
            Write-PSFMessage -Level Verbose -Message "Found $(@($recentCommitChanges).Count) file(s) modified in last $($GitContext.CommitDepth) commit(s)"
        }
    } else {
        $committedChanges = git diff --name-only "$($GitContext.UpstreamBranch)..HEAD" 2>&1 | Where-Object { $_ -is [string] }
        if ($LASTEXITCODE -eq 0 -and $committedChanges) {
            $allModifiedFiles += $committedChanges
            Write-PSFMessage -Level Verbose -Message "Found $(@($committedChanges).Count) committed but not pushed change(s)"
        }
    }

    # Convert to hashtable for O(1) lookups and normalize paths
    if ($allModifiedFiles.Count -gt 0) {
        $allModifiedFiles | Select-Object -Unique | ForEach-Object {
            $filename = $_.Trim()
            if ($filename) {
                $resolvedPath = Join-Path $GitContext.RepoRoot $filename | Resolve-Path -ErrorAction SilentlyContinue
                if ($resolvedPath) {
                    $normalizedPath = $resolvedPath.Path -replace '\\', '/'
                    $snapshot[$normalizedPath] = $true
                }
            }
        }
        Write-PSFMessage -Level Verbose -Message "Initial sweep: $($snapshot.Count) modified files to potentially skip"
    } else {
        Write-PSFMessage -Level Verbose -Message "Initial sweep: No modified files found"
    }

    return $snapshot
}
