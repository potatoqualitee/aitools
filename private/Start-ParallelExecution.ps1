function Start-ParallelExecution {
    <#
    .SYNOPSIS
        Manages runspace pool for parallel file/batch processing.

    .DESCRIPTION
        Creates and manages a runspace pool to process multiple batches in parallel.
        Each runspace imports the module and calls Invoke-AITool recursively with
        -NoParallel to prevent nested parallelization.

    .PARAMETER Batches
        Array of batches, where each batch is an array of file paths.

    .PARAMETER ToolName
        The AI tool to use for processing.

    .PARAMETER PromptText
        The prompt text to use.

    .PARAMETER MaxThreads
        Maximum number of concurrent threads.

    .PARAMETER ContextFiles
        Array of static context file paths.

    .PARAMETER Model
        The model to use.

    .PARAMETER ReasoningEffort
        The reasoning effort level.

    .PARAMETER DisableRetry
        Whether to disable retry logic.

    .PARAMETER MaxRetryMinutes
        Maximum retry time in minutes.

    .PARAMETER SkipModified
        Whether to skip modified files.

    .PARAMETER BatchSize
        The batch size being used.

    .PARAMETER ContextFilter
        Optional scriptblock for dynamic context.

    .PARAMETER ContextFilterBase
        Base directories for context filter.

    .PARAMETER MaxErrors
        Maximum errors before bail-out.

    .PARAMETER MaxTokenErrors
        Maximum token errors before bail-out.

    .PARAMETER ModuleRoot
        The module root path for importing in runspaces.

    .PARAMETER ErrorCountRef
        Reference to error count variable.

    .PARAMETER TokenErrorCountRef
        Reference to token error count variable.

    .PARAMETER BailedOutRef
        Reference to bailed out flag.

    .OUTPUTS
        Results are output directly to the pipeline as they complete.

    .EXAMPLE
        $params = @{
            Batches    = $batches
            ToolName   = "Claude"
            PromptText = "Review code"
            MaxThreads = 3
            ModuleRoot = $ModuleRoot
        }
        Start-ParallelExecution @params
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Batches,

        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$PromptText,

        [Parameter()]
        [int]$MaxThreads = 3,

        [Parameter()]
        [string[]]$ContextFiles,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$ReasoningEffort,

        [Parameter()]
        [switch]$DisableRetry,

        [Parameter()]
        [int]$MaxRetryMinutes = 240,

        [Parameter()]
        [switch]$SkipModified,

        [Parameter()]
        [int]$BatchSize = 1,

        [Parameter()]
        [scriptblock]$ContextFilter,

        [Parameter()]
        [string[]]$ContextFilterBase,

        [Parameter()]
        [int]$MaxErrors = 10,

        [Parameter()]
        [int]$MaxTokenErrors = 3,

        [Parameter(Mandatory)]
        [string]$ModuleRoot,

        [Parameter(Mandatory)]
        [ref]$ErrorCountRef,

        [Parameter(Mandatory)]
        [ref]$TokenErrorCountRef,

        [Parameter(Mandatory)]
        [ref]$BailedOutRef
    )

    $totalFiles = ($Batches | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum

    if ($BatchSize -gt 1) {
        Write-PSFMessage -Level Verbose -Message "Processing $totalFiles files in $($Batches.Count) batches in parallel (max $MaxThreads concurrent batches)"
    } else {
        Write-PSFMessage -Level Verbose -Message "Processing $totalFiles files in parallel (max $MaxThreads concurrent)"
    }

    $parallelStartTime = Get-Date
    $allDurations = [System.Collections.ArrayList]::new()

    # Get the module path for loading in runspaces
    $modulePsmPath = Join-Path $ModuleRoot "aitools.psm1"

    # Create runspace pool
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
    $pool.ApartmentState = "MTA"
    $pool.Open()

    $runspaces = @()

    # Create scriptblock for parallel execution
    $scriptblock = {
        param(
            $ModulePath,
            $BatchFiles,
            $Prompt,
            $Tool,
            $Context,
            $Model,
            $ReasoningEffort,
            $DisableRetry,
            $MaxRetryMinutes,
            $SkipModified,
            $BatchSize,
            $ContextFilter,
            $ContextFilterBase
        )

        # Set environment variables for LiteLLM
        $env:LITELLM_NUM_RETRIES = '0'

        # Import the module
        Import-Module $ModulePath -ErrorAction Stop

        # Build parameters for recursive call
        $params = @{
            Path       = $BatchFiles
            Prompt     = $Prompt
            Tool       = $Tool
            NoParallel = $true
            BatchSize  = $BatchSize
        }

        if ($Context) { $params['Context'] = $Context }
        if ($Model) { $params['Model'] = $Model }
        if ($ReasoningEffort) { $params['ReasoningEffort'] = $ReasoningEffort }
        if ($DisableRetry) { $params['DisableRetry'] = $DisableRetry }
        if ($MaxRetryMinutes) { $params['MaxRetryMinutes'] = $MaxRetryMinutes }
        if ($SkipModified) { $params['SkipModified'] = $SkipModified }
        if ($ContextFilter) { $params['ContextFilter'] = $ContextFilter }
        if ($ContextFilterBase) { $params['ContextFilterBase'] = $ContextFilterBase }

        Invoke-AITool @params
    }

    try {
        # Create and start runspaces for each batch
        $batchIndex = 0
        foreach ($batch in $Batches) {
            $batchIndex++
            $batchFileNames = ($batch | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
            Write-PSFMessage -Level Debug -Message "Queuing batch $batchIndex of $($Batches.Count) for parallel processing: $batchFileNames"

            $progressParams = @{
                Activity        = "Starting parallel processing with $ToolName"
                Status          = "Queuing batch $batchIndex/$($Batches.Count) ($($batch.Count) file(s))"
                PercentComplete = ($batchIndex / $Batches.Count) * 100
            }
            Write-Progress @progressParams

            $runspace = [PowerShell]::Create()
            $null = $runspace.AddScript($scriptblock)
            $null = $runspace.AddArgument($modulePsmPath)
            $null = $runspace.AddArgument($batch)
            $null = $runspace.AddArgument($PromptText)
            $null = $runspace.AddArgument($ToolName)
            $null = $runspace.AddArgument($ContextFiles)
            $null = $runspace.AddArgument($Model)
            $null = $runspace.AddArgument($ReasoningEffort)
            $null = $runspace.AddArgument($DisableRetry)
            $null = $runspace.AddArgument($MaxRetryMinutes)
            $null = $runspace.AddArgument($SkipModified)
            $null = $runspace.AddArgument($BatchSize)
            $null = $runspace.AddArgument($ContextFilter)
            $null = $runspace.AddArgument($ContextFilterBase)
            $runspace.RunspacePool = $pool

            $runspaces += [PSCustomObject]@{
                Pipe   = $runspace
                Status = $runspace.BeginInvoke()
                Batch  = $batch
                Index  = $batchIndex
            }
        }

        Write-PSFMessage -Level Verbose -Message "All runspaces started, waiting for completion and streaming results..."
        Write-Progress -Activity "Starting parallel processing with $ToolName" -Completed

        $processingActivity = if ($BatchSize -gt 1) { "Processing batches in parallel with $ToolName" } else { "Processing files in parallel with $ToolName" }
        Write-Progress -Activity $processingActivity -Status "Waiting for results..." -PercentComplete 0

        # Poll runspaces and output results as they complete
        $completedBatchCount = 0
        $totalBatches = $Batches.Count

        while ($runspaces.Count -gt 0 -and -not $BailedOutRef.Value) {
            foreach ($runspace in @($runspaces)) {
                if ($runspace.Status.IsCompleted) {
                    try {
                        $result = $runspace.Pipe.EndInvoke($runspace.Status)
                        if ($result) {
                            $completedBatchCount++

                            if ($BatchSize -gt 1) {
                                $batchFileNames = ($runspace.Batch | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
                                Write-PSFMessage -Level Verbose -Message "Completed batch $completedBatchCount of $totalBatches ($($runspace.Batch.Count) files)"
                                $progressParams = @{
                                    Activity        = $processingActivity
                                    Status          = "Completed batch: $batchFileNames ($completedBatchCount/$totalBatches)"
                                    PercentComplete = ($completedBatchCount / $totalBatches) * 100
                                }
                            } else {
                                $fileName = [System.IO.Path]::GetFileName($runspace.Batch[0])
                                Write-PSFMessage -Level Verbose -Message "Completed $completedBatchCount of $totalBatches files"
                                $progressParams = @{
                                    Activity        = $processingActivity
                                    Status          = "Completed: $fileName ($completedBatchCount/$totalBatches)"
                                    PercentComplete = ($completedBatchCount / $totalBatches) * 100
                                }
                            }
                            Write-Progress @progressParams

                            # Process results
                            if ($result -is [array]) {
                                foreach ($r in $result) {
                                    if ($r.Duration) {
                                        $null = $allDurations.Add($r.Duration.TotalSeconds)
                                    }
                                    # Check for errors
                                    if ($r.Success -eq $false) {
                                        $resultText = $r.Result | Out-String
                                        $trackingParams = @{
                                            ResultText      = $resultText
                                            Success         = $false
                                            MaxErrors       = $MaxErrors
                                            MaxTokenErrors  = $MaxTokenErrors
                                            ErrorCount      = $ErrorCountRef
                                            TokenErrorCount = $TokenErrorCountRef
                                        }
                                        $tracking = Update-ErrorTracking @trackingParams
                                        if ($tracking.ShouldBailOut) {
                                            $BailedOutRef.Value = $true
                                        }
                                    }
                                    $r  # Output to pipeline
                                }
                            } else {
                                if ($result.Duration) {
                                    $null = $allDurations.Add($result.Duration.TotalSeconds)
                                }
                                if ($result.Success -eq $false) {
                                    $resultText = $result.Result | Out-String
                                    $trackingParams = @{
                                        ResultText      = $resultText
                                        Success         = $false
                                        MaxErrors       = $MaxErrors
                                        MaxTokenErrors  = $MaxTokenErrors
                                        ErrorCount      = $ErrorCountRef
                                        TokenErrorCount = $TokenErrorCountRef
                                    }
                                    $tracking = Update-ErrorTracking @trackingParams
                                    if ($tracking.ShouldBailOut) {
                                        $BailedOutRef.Value = $true
                                    }
                                }
                                $result  # Output to pipeline
                            }
                        } else {
                            $completedBatchCount++
                            if ($BatchSize -gt 1) {
                                $batchFileNames = ($runspace.Batch | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', '
                                Write-PSFMessage -Level Verbose -Message "Skipped batch (fresh check): $batchFileNames"
                            } else {
                                Write-PSFMessage -Level Verbose -Message "Skipped (fresh check): $($runspace.Batch[0])"
                            }
                        }
                    } catch {
                        $batchDesc = if ($BatchSize -gt 1) { "batch $($runspace.Index)" } else { $runspace.Batch[0] }
                        Write-PSFMessage -Level Error -Message "Error retrieving result for $batchDesc : $_"
                    } finally {
                        $runspace.Pipe.Dispose()
                        $runspaces = $runspaces | Where-Object { $_ -ne $runspace }
                    }
                }
            }

            if ($runspaces.Count -gt 0) {
                Start-Sleep -Milliseconds 100
            }
        }

        # Clean up remaining runspaces if bailed out
        if ($BailedOutRef.Value -and $runspaces.Count -gt 0) {
            Write-PSFMessage -Level Warning -Message "Cleaning up $($runspaces.Count) remaining runspace(s) after bail-out"
            foreach ($runspace in $runspaces) {
                try {
                    $runspace.Pipe.Stop()
                    $runspace.Pipe.Dispose()
                } catch {
                    Write-PSFMessage -Level Debug -Message "Error disposing runspace: $_"
                }
            }
        }

        Write-PSFMessage -Level Verbose -Message "All parallel processing complete"
        Write-Progress -Activity $processingActivity -Completed

        # Report timing statistics
        $parallelEndTime = Get-Date
        $totalParallelTime = ($parallelEndTime - $parallelStartTime).TotalSeconds
        $totalSequentialTime = ($allDurations | Measure-Object -Sum).Sum
        $timeSaved = $totalSequentialTime - $totalParallelTime
        $percentSaved = if ($totalSequentialTime -gt 0) { ($timeSaved / $totalSequentialTime) * 100 } else { 0 }

        Write-PSFMessage -Level Verbose -Message "Parallel execution completed in $([Math]::Round($totalParallelTime, 1))s vs estimated sequential time of $([Math]::Round($totalSequentialTime, 1))s"
        if ($timeSaved -gt 0) {
            Write-PSFMessage -Level Verbose -Message "Time saved: $([Math]::Round($timeSaved, 1))s ($([Math]::Round($percentSaved, 1))% faster)"
        }

    } finally {
        # Clean up runspace pool
        if ($pool) {
            Write-PSFMessage -Level Verbose -Message "Cleaning up runspace pool"
            foreach ($runspace in $runspaces) {
                if ($runspace.Pipe) {
                    try {
                        $runspace.Pipe.Stop()
                        $runspace.Pipe.Dispose()
                    } catch {
                        Write-PSFMessage -Level Debug -Message "Error disposing runspace: $_"
                    }
                }
            }
            try {
                $pool.Close()
                $pool.Dispose()
                Write-PSFMessage -Level Verbose -Message "Runspace pool cleaned up successfully"
            } catch {
                Write-PSFMessage -Level Warning -Message "Error closing runspace pool: $_"
            }
        }
    }
}
