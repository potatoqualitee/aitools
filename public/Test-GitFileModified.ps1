function Test-GitFileModified {
    <#
    .SYNOPSIS
        Tests if a file has been modified in git.

    .DESCRIPTION
        Checks if a file has uncommitted changes, staged changes, or unpushed commits.
        Returns $true if the file is modified, $false if clean.
        Uses begin block to cache git repository context, making it efficient for
        pipeline operations while still checking fresh per-file git status.

    .PARAMETER Path
        The file path to check. Can be absolute or relative.

    .PARAMETER CommitDepth
        When on main/master/trunk branch, specifies how many recent commits to check
        for file modifications. Defaults to 10.
        On feature branches, checks ALL commits in the branch (ignores this parameter).

    .EXAMPLE
        Test-GitFileModified -Path "C:\repo\file.ps1"
        Returns $true if file.ps1 has any uncommitted, staged, or unpushed changes.

    .EXAMPLE
        Get-ChildItem *.ps1 | Where-Object { -not (Test-GitFileModified -Path $_.FullName) }
        Gets all .ps1 files that have NOT been modified.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$CommitDepth = 10
    )

    begin {
        # Cache git repository context once for all pipeline items
        $script:gitContextCache = $null

        try {
            # Check if we're in a git repository
            $null = git rev-parse --is-inside-work-tree 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-PSFMessage -Level Verbose -Message "Not in a git repository"
                $script:gitContextCache = @{ InRepo = $false }
                return
            }

            # Get repo root
            $repoRoot = git rev-parse --show-toplevel 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-PSFMessage -Level Warning -Message "Could not determine repo root"
                $script:gitContextCache = @{ InRepo = $false }
                return
            }
            $repoRoot = $repoRoot -replace '/', '\'

            # Get current branch and upstream info
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-PSFMessage -Level Warning -Message "Could not determine current branch"
                $script:gitContextCache = @{ InRepo = $false }
                return
            }

            $upstreamBranch = git symbolic-ref refs/remotes/origin/HEAD 2>&1 | ForEach-Object { $_ -replace 'refs/remotes/', '' }
            $hasUpstream = $LASTEXITCODE -eq 0

            if (-not $hasUpstream) {
                Write-PSFMessage -Level Verbose -Message "No upstream branch found, using local commit history"
            }

            $upstreamBranchName = if ($hasUpstream) { $upstreamBranch -replace '^origin/', '' } else { $null }
            $isOnMainBranch = $currentBranch -in @('main', 'master', 'trunk', $upstreamBranchName)

            # Cache context
            $script:gitContextCache = @{
                InRepo = $true
                RepoRoot = $repoRoot
                CurrentBranch = $currentBranch
                UpstreamBranch = $upstreamBranch
                HasUpstream = $hasUpstream
                IsOnMainBranch = $isOnMainBranch
            }

            Write-PSFMessage -Level Verbose -Message "Git context cached: Branch=$currentBranch, IsMain=$isOnMainBranch, HasUpstream=$hasUpstream"
        } catch {
            Write-PSFMessage -Level Warning -Message "Error initializing git context: $_"
            $script:gitContextCache = @{ InRepo = $false }
        }
    }

    process {
        try {
            # Quick exit if not in repo
            if (-not $script:gitContextCache.InRepo) {
                return $false
            }

            # Normalize paths using cached repo root
            $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
            if (-not $resolvedPath) {
                Write-PSFMessage -Level Warning -Message "Could not resolve path: $Path"
                return $false
            }

            $normalizedPath = $resolvedPath.Path -replace '\\', '/'
            $relativePath = $normalizedPath -replace [regex]::Escape($script:gitContextCache.RepoRoot), '' -replace '^[/\\]', '' -replace '\\', '/'

            Write-PSFMessage -Level Verbose -Message "Checking if file is modified: $relativePath"

            # Check uncommitted working tree changes
            $workingTreeCheck = git diff --name-only -- $relativePath 2>&1
            if ($LASTEXITCODE -eq 0 -and $workingTreeCheck) {
                Write-PSFMessage -Level Verbose -Message "File has uncommitted changes: $relativePath"
                return $true
            }

            # Check staged changes
            $stagedCheck = git diff --name-only --cached -- $relativePath 2>&1
            if ($LASTEXITCODE -eq 0 -and $stagedCheck) {
                Write-PSFMessage -Level Verbose -Message "File has staged changes: $relativePath"
                return $true
            }

            # Check commit history based on branch type
            if ($script:gitContextCache.IsOnMainBranch) {
                # On main/master/trunk: check only recent commits (use CommitDepth)
                if ($CommitDepth -gt 0) {
                    $recentCommitCheck = git log -n $CommitDepth --name-only --pretty=format: -- $relativePath 2>&1 | Where-Object { $_.Trim() }
                    if ($LASTEXITCODE -eq 0 -and $recentCommitCheck) {
                        Write-PSFMessage -Level Verbose -Message "File modified in last $CommitDepth commits: $relativePath"
                        return $true
                    }
                }
            } else {
                # On feature branch: check ALL commits in branch (ignore CommitDepth)
                if ($script:gitContextCache.HasUpstream) {
                    $committedCheck = git diff --name-only "$($script:gitContextCache.UpstreamBranch)..HEAD" -- $relativePath 2>&1
                    if ($LASTEXITCODE -eq 0 -and $committedCheck) {
                        Write-PSFMessage -Level Verbose -Message "File has unpushed commits in feature branch: $relativePath"
                        return $true
                    }
                } else {
                    # No upstream, check local commit history
                    if ($CommitDepth -gt 0) {
                        $recentCommitCheck = git log -n $CommitDepth --name-only --pretty=format: -- $relativePath 2>&1 | Where-Object { $_.Trim() }
                        if ($LASTEXITCODE -eq 0 -and $recentCommitCheck) {
                            Write-PSFMessage -Level Verbose -Message "File modified in last $CommitDepth commits: $relativePath"
                            return $true
                        }
                    }
                }
            }

            Write-PSFMessage -Level Verbose -Message "File is clean: $relativePath"
            return $false

        } catch {
            Write-PSFMessage -Level Warning -Message "Error checking git status for $Path : $_"
            return $false
        }
    }
}
