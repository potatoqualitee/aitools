function Initialize-GitContext {
    <#
    .SYNOPSIS
        Initializes git repository context for -SkipModified functionality.

    .DESCRIPTION
        Sets up git repository context including current branch, upstream branch,
        and determines if on main branch. Used by Invoke-AITool for the -SkipModified
        feature to detect modified files.

    .PARAMETER CommitDepth
        When on the main branch, specifies how many recent commits to check for
        file modifications. Defaults to 10.

    .OUTPUTS
        [hashtable] with keys:
        - UpstreamBranch: The remote default branch (e.g., origin/main)
        - IsOnMainBranch: Whether currently on main/master/trunk
        - CommitDepth: Number of commits to check on main branch
        - CurrentBranch: The current branch name
        - RepoRoot: The repository root path (normalized with backslashes)

        Returns $null if not in a git repository or unable to determine context.

    .EXAMPLE
        $gitContext = Initialize-GitContext -CommitDepth 5
        if ($gitContext) {
            Write-Host "On branch: $($gitContext.CurrentBranch)"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$CommitDepth = 10
    )

    try {
        # Check if we're in a git repository
        $null = git rev-parse --is-inside-work-tree 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-PSFMessage -Level Warning -Message "Not in a git repository. Git context will not be available."
            return $null
        }

        Write-PSFMessage -Level Verbose -Message "Git repository detected, initializing context"

        # Get and cache repo root
        $repoRoot = git rev-parse --show-toplevel 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-PSFMessage -Level Warning -Message "Could not determine repo root."
            return $null
        }
        $repoRoot = $repoRoot -replace '/', '\'
        Write-PSFMessage -Level Verbose -Message "Repository root: $repoRoot"

        # Get current branch name
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-PSFMessage -Level Warning -Message "Could not determine current branch."
            return $null
        }
        Write-PSFMessage -Level Verbose -Message "Current branch: $currentBranch"

        # Get the remote's default branch (what origin/HEAD points to)
        $upstreamBranch = git symbolic-ref refs/remotes/origin/HEAD 2>&1 | ForEach-Object { $_ -replace 'refs/remotes/', '' }
        if ($LASTEXITCODE -ne 0) {
            Write-PSFMessage -Level Warning -Message "Could not determine remote default branch."
            return $null
        }
        Write-PSFMessage -Level Verbose -Message "Upstream branch: $upstreamBranch"

        # Check if we're on the main/upstream branch (main, master, trunk, or whatever upstream points to)
        $upstreamBranchName = $upstreamBranch -replace '^origin/', ''
        $isOnMainBranch = $currentBranch -in @('main', 'master', 'trunk', $upstreamBranchName)

        if ($isOnMainBranch) {
            Write-PSFMessage -Level Warning -Message "You are on the main branch '$currentBranch'. Using -CommitDepth $CommitDepth to check recent commit history for modified files."
        }

        return @{
            UpstreamBranch = $upstreamBranch
            IsOnMainBranch = $isOnMainBranch
            CommitDepth    = $CommitDepth
            CurrentBranch  = $currentBranch
            RepoRoot       = $repoRoot
        }
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to initialize git context: $_"
        return $null
    }
}
