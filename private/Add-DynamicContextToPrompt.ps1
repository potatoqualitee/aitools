function Add-DynamicContextToPrompt {
    <#
    .SYNOPSIS
        Executes ContextFilter scriptblock and adds derived context files to the prompt.

    .DESCRIPTION
        Processes each input file through the ContextFilter scriptblock to derive related
        context files (e.g., finding English originals for French translations). Handles
        path resolution, deduplication, and adds the content to the prompt.

    .PARAMETER BasePrompt
        The prompt text to add context to.

    .PARAMETER InputFiles
        Array of input file paths to process through the ContextFilter.

    .PARAMETER ContextFilter
        A scriptblock that transforms each input filename to derive a matching context file.
        Receives the file path via $_ and should return the derived filename or path.

    .PARAMETER ContextFilterBase
        Base directory or directories to search for files derived by ContextFilter.
        Searched in order, with the source file's directory as fallback.

    .PARAMETER WhatIf
        If specified, returns info about what would be added without modifying the prompt.

    .PARAMETER PSCmdlet
        The PSCmdlet object for ShouldProcess support.

    .OUTPUTS
        [hashtable] with keys:
        - Prompt: The modified prompt with context added
        - AddedFiles: Hashtable of files that were added (for deduplication tracking)
        - Count: Number of unique context files added

    .EXAMPLE
        $params = @{
            BasePrompt    = $prompt
            InputFiles    = @("file.fr.md")
            ContextFilter = { $_ -replace '\.fr\.md$', '.md' }
        }
        $result = Add-DynamicContextToPrompt @params
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$BasePrompt,

        [Parameter(Mandatory)]
        [string[]]$InputFiles,

        [Parameter(Mandatory)]
        [scriptblock]$ContextFilter,

        [Parameter()]
        [string[]]$ContextFilterBase,

        [Parameter()]
        [System.Management.Automation.PSCmdlet]$PSCmdlet
    )

    $modifiedPrompt = $BasePrompt
    $addedDynamicContext = @{}

    Write-PSFMessage -Level Verbose -Message "Processing ContextFilter for $($InputFiles.Count) file(s)"
    Write-PSFMessage -Level Debug -Message "ContextFilter scriptblock: $($ContextFilter.ToString())"
    if ($ContextFilterBase) {
        Write-PSFMessage -Level Debug -Message "ContextFilterBase directories: $($ContextFilterBase -join ', ')"
    }

    foreach ($fileInBatch in $InputFiles) {
        Write-PSFMessage -Level Debug -Message "ContextFilter: Processing input file: $fileInBatch"
        try {
            # Run the scriptblock with $_ set to current file
            $derivedName = $fileInBatch | ForEach-Object $ContextFilter
            Write-PSFMessage -Level Debug -Message "ContextFilter: Scriptblock returned: '$derivedName'"

            if (-not $derivedName) {
                Write-PSFMessage -Level Debug -Message "ContextFilter: Empty result, skipping"
                continue
            }

            # Resolve path
            $derivedPath = $null
            if ([System.IO.Path]::IsPathRooted($derivedName)) {
                Write-PSFMessage -Level Debug -Message "ContextFilter: Derived name is absolute path"
                if (Test-Path $derivedName) {
                    $derivedPath = $derivedName
                    Write-PSFMessage -Level Debug -Message "ContextFilter: Absolute path exists: $derivedPath"
                } else {
                    Write-PSFMessage -Level Debug -Message "ContextFilter: Absolute path does not exist: $derivedName"
                }
            } else {
                # Build list of directories to search
                $searchDirs = @()
                if ($ContextFilterBase) {
                    $searchDirs += $ContextFilterBase
                }
                $searchDirs += Split-Path $fileInBatch -Parent
                Write-PSFMessage -Level Debug -Message "ContextFilter: Search directories (in order): $($searchDirs -join ', ')"

                # Search each directory until we find the file
                foreach ($baseDir in $searchDirs) {
                    $candidatePath = Join-Path $baseDir $derivedName
                    Write-PSFMessage -Level Debug -Message "ContextFilter: Checking candidate path: $candidatePath"
                    if (Test-Path $candidatePath) {
                        $derivedPath = (Resolve-Path $candidatePath).Path
                        Write-PSFMessage -Level Debug -Message "ContextFilter: Found at: $derivedPath"
                        break
                    }
                }
            }

            # Skip if file not found
            if (-not $derivedPath -or -not (Test-Path $derivedPath)) {
                $searchedPath = if ($derivedPath) { $derivedPath } else { $derivedName }
                Write-PSFMessage -Level Warning -Message "ContextFilter derived file not found: $searchedPath (from $fileInBatch)"
                Write-PSFMessage -Level Debug -Message "ContextFilter: File not found after searching all directories"
                continue
            }

            # Skip if derived file is same as input file
            $normalizedDerived = (Resolve-Path $derivedPath).Path -replace '\\', '/'
            $normalizedInput = (Resolve-Path $fileInBatch).Path -replace '\\', '/'
            if ($normalizedDerived -eq $normalizedInput) {
                Write-PSFMessage -Level Debug -Message "ContextFilter: Skipping - derived file same as input: $derivedPath"
                continue
            }

            # Skip if already added (deduplication)
            if ($addedDynamicContext.ContainsKey($normalizedDerived)) {
                Write-PSFMessage -Level Debug -Message "ContextFilter: Skipping duplicate: $derivedPath (already added)"
                continue
            }

            # Add to prompt with ShouldProcess
            $shouldProcess = if ($PSCmdlet) {
                $PSCmdlet.ShouldProcess($derivedPath, "Add dynamic context from ContextFilter")
            } else {
                $true
            }

            if ($shouldProcess) {
                $content = Get-Content -Path $derivedPath -Raw
                $contentLength = if ($content) { $content.Length } else { 0 }
                Write-PSFMessage -Level Debug -Message "ContextFilter: Reading content from $derivedPath ($contentLength chars)"
                $modifiedPrompt += "`n`n--- Dynamic Context from $derivedPath (for $fileInBatch) ---`n$content"
                $addedDynamicContext[$normalizedDerived] = $true
                Write-PSFMessage -Level Verbose -Message "Added dynamic context: $derivedPath (from $fileInBatch)"
            }

        } catch {
            Write-PSFMessage -Level Warning -Message "ContextFilter error for $fileInBatch : $_"
            Write-PSFMessage -Level Debug -Message "ContextFilter: Exception details: $($_.Exception.GetType().Name) - $($_.Exception.Message)"
        }
    }

    if ($addedDynamicContext.Count -gt 0) {
        Write-PSFMessage -Level Verbose -Message "Added $($addedDynamicContext.Count) dynamic context file(s) to prompt"
        Write-PSFMessage -Level Debug -Message "ContextFilter: Dynamic context files added: $($addedDynamicContext.Keys -join ', ')"
    }

    return @{
        Prompt     = $modifiedPrompt
        AddedFiles = $addedDynamicContext
        Count      = $addedDynamicContext.Count
    }
}
