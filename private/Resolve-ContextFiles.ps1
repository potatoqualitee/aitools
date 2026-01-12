function Resolve-ContextFiles {
    <#
    .SYNOPSIS
        Processes the Context parameter and resolves paths to normalized file paths.

    .DESCRIPTION
        Takes an array of context items (FileInfo objects, strings, or other objects with
        FullName/Path properties) and resolves them to normalized file paths using forward
        slashes for cross-platform CLI compatibility.

    .PARAMETER Context
        An array of context items to process. Can be:
        - [System.IO.FileInfo] or [System.IO.FileSystemInfo] objects
        - String paths (resolved if they exist)
        - Objects with FullName or Path properties

    .OUTPUTS
        [string[]] Array of normalized file paths (using forward slashes).
        Empty array if no valid context files found.

    .EXAMPLE
        $contextFiles = Resolve-ContextFiles -Context @("file1.md", "file2.md")

    .EXAMPLE
        $contextFiles = Resolve-ContextFiles -Context (Get-ChildItem *.md)
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Context
    )

    $contextFiles = @()

    if (-not $Context) {
        return $contextFiles
    }

    foreach ($contextItem in $Context) {
        if ($contextItem -is [System.IO.FileInfo] -or $contextItem -is [System.IO.FileSystemInfo]) {
            Write-PSFMessage -Level Verbose -Message "Context item is a file object: $($contextItem.FullName)"
            if (Test-Path $contextItem.FullName) {
                # Normalize path to use forward slashes
                $normalizedContext = $contextItem.FullName -replace '\\', '/'
                $contextFiles += $normalizedContext
            } else {
                Write-PSFMessage -Level Warning -Message "Context file not found: $($contextItem.FullName)"
            }
        } elseif ($contextItem -is [string]) {
            # Resolve the path if it exists
            $resolvedContext = Resolve-Path -Path $contextItem -ErrorAction SilentlyContinue
            if ($resolvedContext) {
                # Normalize path to use forward slashes
                $normalizedContext = $resolvedContext.Path -replace '\\', '/'
                Write-PSFMessage -Level Verbose -Message "Context item resolved to: $normalizedContext"
                $contextFiles += $normalizedContext
            } else {
                Write-PSFMessage -Level Warning -Message "Context path not found: $contextItem"
            }
        } else {
            Write-PSFMessage -Level Verbose -Message "Context item is an object, attempting to get FullName or Path property"
            if ($contextItem.PSObject.Properties['FullName']) {
                # Normalize path to use forward slashes
                $normalizedContext = $contextItem.FullName -replace '\\', '/'
                $contextFiles += $normalizedContext
            } elseif ($contextItem.PSObject.Properties['Path']) {
                # Normalize path to use forward slashes
                $normalizedContext = $contextItem.Path -replace '\\', '/'
                $contextFiles += $normalizedContext
            } else {
                Write-PSFMessage -Level Warning -Message "Could not determine path from context object: $($contextItem.GetType().Name)"
            }
        }
    }

    return $contextFiles
}
