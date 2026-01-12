function New-AIToolResult {
    <#
    .SYNOPSIS
        Creates a standardized result object for AI tool operations.

    .DESCRIPTION
        Creates a consistent PSCustomObject for returning results from Invoke-AITool.
        Ensures all results have the same structure regardless of which code path
        generated them.

    .PARAMETER FileName
        The display name for the file (or "N/A (Chat Mode)" for chat mode).

    .PARAMETER FullPath
        The full path to the file (or description for batch/chat mode).

    .PARAMETER ToolName
        The name of the AI tool used.

    .PARAMETER Model
        The model used (or "Default" if not specified).

    .PARAMETER Result
        The captured output from the tool.

    .PARAMETER StartTime
        The start time of the operation.

    .PARAMETER EndTime
        The end time of the operation.

    .PARAMETER Success
        Whether the operation was successful (exit code 0).

    .PARAMETER BatchFiles
        Array of files in the batch (for batch mode).

    .PARAMETER BatchIndex
        The index of the current batch (optional, for batch naming).

    .PARAMETER BatchSize
        The batch size being used (for determining output naming).

    .OUTPUTS
        [PSCustomObject] with properties:
        - FileName: Display name
        - FullPath: Full path or description
        - Tool: Tool name
        - Model: Model used
        - Result: Captured output
        - StartTime: Operation start
        - EndTime: Operation end
        - Duration: TimeSpan of operation
        - Success: Boolean success indicator
        - BatchFiles: Array of files (always present)

    .EXAMPLE
        $params = @{
            FileName  = "script.ps1"
            FullPath  = "C:\script.ps1"
            ToolName  = "Claude"
            Model     = "opus"
            Result    = "Done"
            StartTime = $start
            EndTime   = Get-Date
            Success   = $true
        }
        $result = New-AIToolResult @params
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [string]$FullPath,

        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Result,

        [Parameter(Mandatory)]
        [datetime]$StartTime,

        [Parameter(Mandatory)]
        [datetime]$EndTime,

        [Parameter(Mandatory)]
        [bool]$Success,

        [Parameter()]
        [string[]]$BatchFiles,

        [Parameter()]
        [int]$BatchIndex,

        [Parameter()]
        [int]$BatchSize = 1
    )

    # Determine display name based on batch mode
    $outputFileName = if ($BatchSize -gt 1 -and $BatchFiles -and $BatchFiles.Count -gt 1) {
        "Batch $BatchIndex ($($BatchFiles.Count) files)"
    } else {
        $FileName
    }

    $outputFullPath = if ($BatchSize -gt 1 -and $BatchFiles -and $BatchFiles.Count -gt 1) {
        "Batch: $($BatchFiles -join ', ')"
    } else {
        $FullPath
    }

    # Ensure BatchFiles is always an array
    $outputBatchFiles = if ($BatchFiles) {
        $BatchFiles
    } else {
        @($FullPath)
    }

    [PSCustomObject]@{
        FileName   = $outputFileName
        FullPath   = $outputFullPath
        Tool       = $ToolName
        Model      = if ($Model) { $Model } else { 'Default' }
        Result     = $Result
        StartTime  = $StartTime
        EndTime    = $EndTime
        Duration   = [timespan]::FromSeconds([Math]::Floor(($EndTime - $StartTime).TotalSeconds))
        Success    = $Success
        BatchFiles = $outputBatchFiles
    }
}
