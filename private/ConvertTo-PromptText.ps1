function ConvertTo-PromptText {
    <#
    .SYNOPSIS
        Converts a prompt parameter to text, detecting if it's a file object, file path, pattern, or string.

    .DESCRIPTION
        Processes the Prompt parameter from Invoke-AITool and converts it to text content.
        Handles FileInfo objects, file paths, glob patterns, and plain strings.
        When reading from files, appends the file path to the content for reference.

    .PARAMETER Prompt
        The prompt to convert. Can be:
        - [System.IO.FileInfo] or [System.IO.FileSystemInfo] object
        - A string containing a file path
        - A string containing a glob pattern (with * or ?)
        - A plain text string

    .OUTPUTS
        [hashtable] with keys:
        - Text: The prompt text content
        - FilePath: The source file path if prompt was from a file, $null otherwise

    .EXAMPLE
        $result = ConvertTo-PromptText -Prompt "Fix this code"
        # Returns @{ Text = "Fix this code"; FilePath = $null }

    .EXAMPLE
        $result = ConvertTo-PromptText -Prompt (Get-ChildItem prompt.md)
        # Returns @{ Text = "<file content>\n\n(File: C:\...\prompt.md)"; FilePath = "C:\...\prompt.md" }

    .EXAMPLE
        $result = ConvertTo-PromptText -Prompt "prompts\*.md"
        # Returns combined content from all matching files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Prompt
    )

    $promptFilePath = $null
    $promptText = $null

    if ($Prompt -is [System.IO.FileInfo] -or $Prompt -is [System.IO.FileSystemInfo]) {
        Write-PSFMessage -Level Verbose -Message "Prompt is a file object: $($Prompt.FullName)"
        if (Test-Path $Prompt.FullName) {
            $promptFilePath = $Prompt.FullName
            $content = Get-Content $Prompt.FullName -Raw
            # Append file path to content
            $promptText = "$content`n`n(File: $($Prompt.FullName))"
        } else {
            Stop-PSFFunction -Message "Prompt file not found: $($Prompt.FullName)" -EnableException $true
            return
        }
    } elseif ($Prompt -is [string]) {
        # Check if it's a file pattern (contains wildcards)
        if ($Prompt -match '[\*\?]') {
            Write-PSFMessage -Level Verbose -Message "Prompt appears to be a file pattern: $Prompt"
            $matchedFiles = Get-ChildItem -Path $Prompt -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }

            if ($matchedFiles) {
                Write-PSFMessage -Level Verbose -Message "Found $($matchedFiles.Count) file(s) matching pattern: $Prompt"
                # For multiple files, use the first one as the prompt file path
                $promptFilePath = $matchedFiles[0].FullName
                # Combine content from all matched files
                $promptText = ($matchedFiles | ForEach-Object {
                    $fileContent = Get-Content $_.FullName -Raw
                    "$fileContent`n`n(File: $($_.FullName))"
                }) -join "`n`n---`n`n"
            } else {
                Write-PSFMessage -Level Verbose -Message "No files matched pattern, treating as plain string"
                $promptText = $Prompt
            }
        }
        # Check if it could be a file path (skip Test-Path for multi-line strings or strings with invalid path chars)
        # This prevents Test-Path from interpreting prompt text as PSDrive names when colons are present
        elseif ($Prompt -notmatch '[\r\n]' -and $Prompt.Length -lt 260 -and (Test-Path $Prompt -ErrorAction SilentlyContinue) -and -not (Test-Path $Prompt -PathType Container)) {
            Write-PSFMessage -Level Verbose -Message "Prompt is a file path: $Prompt"
            $promptFilePath = $Prompt
            $content = Get-Content $Prompt -Raw
            # Append file path to content
            $promptText = "$content`n`n(File: $Prompt)"
        } else {
            Write-PSFMessage -Level Verbose -Message "Prompt is a plain string"
            $promptText = $Prompt
        }
    } else {
        Write-PSFMessage -Level Verbose -Message "Prompt is an object, converting to string"
        $promptText = $Prompt.ToString()
    }

    return @{
        Text     = $promptText
        FilePath = $promptFilePath
    }
}
