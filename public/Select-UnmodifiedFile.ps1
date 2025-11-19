function Select-UnmodifiedFile {
    <#
    .SYNOPSIS
        Filters files to return only those that have NOT been modified in git.

    .DESCRIPTION
        Pipeline filter that checks each file's git status and only passes through
        files that are clean (no uncommitted, staged, or unpushed changes).
        This function checks git status fresh for each file, making it suitable
        for concurrent processes that may be modifying files.

    .PARAMETER InputObject
        The file object(s) to check. Can be FileInfo objects from Get-ChildItem.

    .PARAMETER CommitDepth
        When on main/master/trunk branch, specifies how many recent commits to check
        for file modifications. Defaults to 10.
        On feature branches, checks ALL commits in the branch (ignores this parameter).
        Set to 0 to only check uncommitted/staged changes (ignoring commit history).

    .EXAMPLE
        Get-ChildItem *.ps1 | Select-UnmodifiedFile
        Returns only .ps1 files that have NOT been modified in git.

    .EXAMPLE
        Get-ChildItem *.ps1 | Select-UnmodifiedFile | Measure-Object
        Counts how many .ps1 files are unmodified.

    .EXAMPLE
        Get-ChildItem *.ps1 | Select-UnmodifiedFile -CommitDepth 5
        Returns unmodified files, checking the last 5 commits if on main branch.

    .OUTPUTS
        [System.IO.FileInfo]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$CommitDepth = 10
    )

    begin {
        # Initialize collection for all files to check
        $script:filesToCheck = [System.Collections.Generic.List[object]]::new()

        # We need to defer git repo detection until we see the first file
        # because the repo root depends on where the files are, not where we run from
        $script:repoRoot = $null
        $script:notInGitRepo = $null  # null = not yet determined
        $script:modifiedSnapshot = @{}
        $script:repoInitialized = $false
        $script:commitDepth = $CommitDepth
    }

    process {
        # Get the file path from various possible input types
        $filePath = $null
        if ($InputObject -is [System.IO.FileInfo]) {
            $filePath = $InputObject.FullName
        } elseif ($InputObject -is [string]) {
            $filePath = $InputObject
        } elseif ($InputObject.PSObject.Properties.Name -contains 'FullName') {
            $filePath = $InputObject.FullName
        } elseif ($InputObject.PSObject.Properties.Name -contains 'Path') {
            $filePath = $InputObject.Path
        } else {
            Write-PSFMessage -Level Warning -Message "Could not determine file path from input object"
            return
        }

        # Initialize repo context on first file
        if (-not $script:repoInitialized) {
            $script:repoInitialized = $true

            # Get the directory of the first file to determine repo context
            $fileDir = Split-Path -Path $filePath -Parent
            $originalLocation = Get-Location

            try {
                Set-Location $fileDir

                # Check if we're in a git repository
                $null = git rev-parse --is-inside-work-tree 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-PSFMessage -Level Warning -Message "Not in a git repository. All files will be returned."
                    $script:notInGitRepo = $true
                    return $InputObject
                }

                $script:notInGitRepo = $false
                Write-PSFMessage -Level Verbose -Message "Git repository detected, performing initial sweep"

                # Get repo root and normalize
                $script:repoRoot = git rev-parse --show-toplevel 2>&1
                if ($LASTEXITCODE -eq 0) {
                    # Convert Unix-style path to Windows-style path
                    if ($script:repoRoot -match '^/[a-z]/') {
                        $script:repoRoot = $script:repoRoot -replace '^/([a-z])/', '$1:/' -replace '/', '\'
                    } else {
                        $script:repoRoot = $script:repoRoot -replace '/', '\'
                    }

                    # Ensure repo root is resolved to full path and normalized (lowercase, no trailing slash)
                    $resolvedRepoRoot = Resolve-Path -Path $script:repoRoot -ErrorAction Stop
                    $script:repoRoot = $resolvedRepoRoot.Path.TrimEnd('\').ToLower()

                    Write-PSFMessage -Level Verbose -Message "Repo root: $($script:repoRoot)"

                    # Get current branch info
                    $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
                    $upstreamBranch = git symbolic-ref refs/remotes/origin/HEAD 2>&1 | ForEach-Object { $_ -replace 'refs/remotes/', '' }
                    $upstreamBranchName = $upstreamBranch -replace '^origin/', ''
                    $isOnMainBranch = $currentBranch -in @('main', 'master', 'trunk', $upstreamBranchName)

                    $allModified = @()

                    # Get all modified files in bulk
                    $allModified += git diff --name-only 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }
                    $allModified += git diff --name-only --cached 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }

                    # Check commit history based on branch type
                    if ($isOnMainBranch) {
                        if ($script:commitDepth -gt 0) {
                            $allModified += git log -n $script:commitDepth --name-only --pretty=format: 2>&1 | Where-Object { $_ -is [string] -and $_.Trim() }
                        }
                    } else {
                        $allModified += git diff --name-only "$upstreamBranch..HEAD" 2>&1 | Where-Object { $_ -is [string] }
                    }

                    # Store relative paths
                    $allModified | Select-Object -Unique | ForEach-Object {
                        $filename = $_.Trim()
                        if ($filename) {
                            $relativePath = ($filename -replace '/', '\').ToLower()
                            $script:modifiedSnapshot[$relativePath] = $true
                        }
                    }

                    Write-PSFMessage -Level Verbose -Message "Initial sweep: $($script:modifiedSnapshot.Count) modified files in snapshot"
                }
            } catch {
                Write-PSFMessage -Level Warning -Message "Failed to initialize git context: $_"
                $script:notInGitRepo = $true
                return $InputObject
            } finally {
                Set-Location $originalLocation
            }
        }

        # If not in a git repo, pass everything through
        if ($script:notInGitRepo) {
            return $InputObject
        }

        # Stage 1: Quick bulk check - if in snapshot, skip immediately
        try {
            # Normalize the file path to match git's relative path format
            $resolvedPath = (Resolve-Path -Path $filePath -ErrorAction SilentlyContinue).Path
            if ($resolvedPath) {
                # Normalize to lowercase and ensure no trailing slash
                $normalizedFullPath = $resolvedPath.TrimEnd('\').ToLower()

                # Calculate relative path by removing repo root
                # Both paths are now lowercase and without trailing slashes
                if ($normalizedFullPath.StartsWith($script:repoRoot + '\')) {
                    $relativePath = $normalizedFullPath.Substring($script:repoRoot.Length + 1)
                } elseif ($normalizedFullPath -eq $script:repoRoot) {
                    # File is at repo root
                    $relativePath = ''
                } else {
                    Write-PSFMessage -Level Warning -Message "File path not under repo root: $filePath"
                    return
                }

                if ($script:modifiedSnapshot.ContainsKey($relativePath)) {
                    Write-PSFMessage -Level Verbose -Message "Skipping (bulk filter): $filePath (matched: $relativePath)"
                    return
                }
            } else {
                Write-PSFMessage -Level Warning -Message "Could not resolve path: $filePath"
                return
            }
        } catch {
            # If path conversion fails, skip the file to be safe
            Write-PSFMessage -Level Warning -Message "Could not check file path: $filePath - $_"
            return
        }

        # Passed Stage 1, collect for batch processing in end block
        $script:filesToCheck.Add(@{
            InputObject = $InputObject
            FilePath = $filePath
        })
    }

    end {
        # If not in git repo or no files to check, we're done
        if ($script:notInGitRepo -or $script:filesToCheck.Count -eq 0) {
            return
        }

        Write-PSFMessage -Level Verbose -Message "Stage 2: Fresh verification for $($script:filesToCheck.Count) files that passed initial filter"

        # Stage 2: Batch fresh verification for all files that passed Stage 1
        # This catches files modified by concurrent processes after initial sweep

        # Get fresh git status for working tree and staged changes (bulk operations)
        $freshWorkingTree = @{}
        $freshStaged = @{}

        $workingTreeFiles = git diff --name-only 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }
        if ($LASTEXITCODE -eq 0 -and $workingTreeFiles) {
            $workingTreeFiles | ForEach-Object {
                # Convert git path to full path and normalize
                $gitRelPath = $_.Trim()
                if ($gitRelPath) {
                    # Git returns forward slashes, convert to backslashes for Windows
                    $gitRelPathNormalized = $gitRelPath -replace '/', '\'
                    $fullPath = Join-Path $script:repoRoot $gitRelPathNormalized
                    $resolvedPath = Resolve-Path -Path $fullPath -ErrorAction SilentlyContinue
                    if ($resolvedPath) {
                        # Normalize: lowercase, no trailing slash
                        $freshWorkingTree[$resolvedPath.Path.TrimEnd('\').ToLower()] = $true
                    }
                }
            }
        }

        $stagedFiles = git diff --name-only --cached 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }
        if ($LASTEXITCODE -eq 0 -and $stagedFiles) {
            $stagedFiles | ForEach-Object {
                # Convert git path to full path and normalize
                $gitRelPath = $_.Trim()
                if ($gitRelPath) {
                    # Git returns forward slashes, convert to backslashes for Windows
                    $gitRelPathNormalized = $gitRelPath -replace '/', '\'
                    $fullPath = Join-Path $script:repoRoot $gitRelPathNormalized
                    $resolvedPath = Resolve-Path -Path $fullPath -ErrorAction SilentlyContinue
                    if ($resolvedPath) {
                        # Normalize: lowercase, no trailing slash
                        $freshStaged[$resolvedPath.Path.TrimEnd('\').ToLower()] = $true
                    }
                }
            }
        }

        Write-PSFMessage -Level Verbose -Message "Fresh check: $($freshWorkingTree.Count) uncommitted, $($freshStaged.Count) staged"

        # Check each file against fresh status
        foreach ($fileInfo in $script:filesToCheck) {
            $filePath = $fileInfo.FilePath
            $resolvedPath = Resolve-Path -Path $filePath -ErrorAction SilentlyContinue

            if (-not $resolvedPath) {
                Write-PSFMessage -Level Warning -Message "Could not resolve path: $filePath"
                continue
            }

            # Normalize: lowercase, no trailing slash
            $normalizedPath = $resolvedPath.Path.TrimEnd('\').ToLower()

            # Check if file appears in fresh working tree or staged changes
            if ($freshWorkingTree.ContainsKey($normalizedPath)) {
                Write-PSFMessage -Level Verbose -Message "Skipping (fresh uncommitted): $filePath"
                continue
            }

            if ($freshStaged.ContainsKey($normalizedPath)) {
                Write-PSFMessage -Level Verbose -Message "Skipping (fresh staged): $filePath"
                continue
            }

            # File is clean in both checks, return it
            Write-PSFMessage -Level Verbose -Message "File is clean, passing through: $filePath"
            $fileInfo.InputObject
        }
    }
}
