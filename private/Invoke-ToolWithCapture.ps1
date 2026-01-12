function Invoke-ToolWithCapture {
    <#
    .SYNOPSIS
        Executes an AI tool and captures output with proper encoding handling.

    .DESCRIPTION
        Wraps the execution of AI CLI tools with output capturing, retry logic,
        and proper encoding handling. Supports both raw mode (no capturing) and
        captured mode (for structured output).

    .PARAMETER ToolName
        The name of the AI tool (e.g., Claude, Aider, Codex).

    .PARAMETER ToolCommand
        The command to execute (e.g., "claude", "aider").

    .PARAMETER Arguments
        Array of arguments to pass to the tool.

    .PARAMETER FullPrompt
        The full prompt text to send to the tool.

    .PARAMETER Raw
        If specified, executes in raw mode without capturing output.

    .PARAMETER DisableRetry
        Disable automatic retry with exponential backoff.

    .PARAMETER MaxRetryMinutes
        Maximum total time in minutes for all retry delays.

    .PARAMETER Context
        Descriptive context for logging (e.g., "Processing script.ps1").

    .PARAMETER BatchSize
        The batch size being used (for descriptive logging).

    .PARAMETER BatchFilesCount
        The number of files in the current batch.

    .PARAMETER TargetFile
        The target file being processed.

    .OUTPUTS
        [hashtable] with keys:
        - Output: The captured output (or $null in raw mode)
        - ExitCode: The exit code from the tool
        - Success: Boolean indicating if exit code was 0

    .EXAMPLE
        $params = @{
            ToolName    = "Claude"
            ToolCommand = "claude"
            Arguments   = @("--model", "opus")
            FullPrompt  = "Hello"
            Context     = "Chat mode"
        }
        $result = Invoke-ToolWithCapture @params
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$ToolCommand,

        [Parameter()]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$FullPrompt,

        [Parameter()]
        [switch]$Raw,

        [Parameter()]
        [switch]$DisableRetry,

        [Parameter()]
        [int]$MaxRetryMinutes = 240,

        [Parameter()]
        [string]$Context = "Operation",

        [Parameter()]
        [int]$BatchSize = 1,

        [Parameter()]
        [int]$BatchFilesCount = 1,

        [Parameter()]
        [string]$TargetFile
    )

    $batchDesc = if ($BatchSize -gt 1) { "batch of $BatchFilesCount file(s)" } else { $TargetFile }

    if ($Raw) {
        Write-PSFMessage -Level Verbose -Message "Executing in raw mode (no output capturing)"

        if ($ToolName -eq 'Aider') {
            $originalOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $env:PYTHONIOENCODING = 'utf-8'
            $env:LITELLM_NUM_RETRIES = '0'

            & $ToolCommand @Arguments 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    Write-PSFMessage -Level Debug -Message $_.Exception.Message
                } else {
                    $_
                }
            }

            [Console]::OutputEncoding = $originalOutputEncoding
            Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
        } elseif ($ToolName -eq 'Codex') {
            $originalOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

            & $ToolCommand @Arguments 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    Write-PSFMessage -Level Debug -Message $_.Exception.Message
                } else {
                    $_
                }
            }

            [Console]::OutputEncoding = $originalOutputEncoding
        } else {
            $originalOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

            $FullPrompt | & $ToolCommand @Arguments 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    Write-PSFMessage -Level Debug -Message $_.Exception.Message
                } else {
                    $_
                }
            }

            [Console]::OutputEncoding = $originalOutputEncoding
        }

        $exitCode = $LASTEXITCODE
        Write-PSFMessage -Level Verbose -Message "Tool exited with code: $exitCode"

        if ($exitCode -eq 0) {
            Write-PSFMessage -Level Verbose -Message "Batch processed successfully"
        } else {
            Write-PSFMessage -Level Warning -Message "Failed to process batch (exit code: $exitCode)"
        }

        return @{
            Output   = $null
            ExitCode = $exitCode
            Success  = ($exitCode -eq 0)
        }
    }

    # Captured mode - create temp file for output redirection
    $tempOutputFile = [System.IO.Path]::GetTempFileName()
    Write-PSFMessage -Level Verbose -Message "Redirecting output to temp file: $tempOutputFile"

    $capturedOutput = $null
    $toolExitCode = 0

    try {
        if ($ToolName -eq 'Aider') {
            Write-PSFMessage -Level Verbose -Message "Executing Aider with native --read context files"
            $originalOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $env:PYTHONIOENCODING = 'utf-8'
            $env:LITELLM_NUM_RETRIES = '0'

            $executionScriptBlock = {
                $outFileParams = @{
                    FilePath = $tempOutputFile
                    Encoding = 'utf8'
                }
                & $ToolCommand @Arguments *>&1 | Tee-Object @outFileParams
            }.GetNewClosure()

            $capturedOutput = Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$Context"
            $toolExitCode = $LASTEXITCODE

            if ($capturedOutput -is [array]) {
                $capturedOutput = $capturedOutput | Out-String
            }

            [Console]::OutputEncoding = $originalOutputEncoding
            Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue

        } elseif ($ToolName -eq 'Codex') {
            Write-PSFMessage -Level Verbose -Message "Executing Codex (prompt in arguments)"

            $executionScriptBlock = [ScriptBlock]::Create(@"
& '$ToolCommand' $($Arguments | ForEach-Object { if ($_ -match '\s') { "'$($_.Replace("'", "''"))'" } else { $_ } }) *>&1 | Out-File -FilePath '$tempOutputFile' -Encoding utf8
"@)

            Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$Context"
            $toolExitCode = $LASTEXITCODE

            $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8

        } elseif ($ToolName -eq 'Cursor') {
            Write-PSFMessage -Level Verbose -Message "Executing Cursor (prompt in arguments)"

            $executionScriptBlock = {
                & $ToolCommand @Arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
            }.GetNewClosure()

            Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$Context"
            $toolExitCode = $LASTEXITCODE

            $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8

        } else {
            Write-PSFMessage -Level Verbose -Message "Piping combined prompt to $ToolName"

            $executionScriptBlock = {
                $FullPrompt | & $ToolCommand @Arguments *>&1 | Out-File -FilePath $tempOutputFile -Encoding utf8
            }.GetNewClosure()

            Invoke-WithRetry -ScriptBlock $executionScriptBlock -EnableRetry:(-not $DisableRetry) -MaxTotalMinutes $MaxRetryMinutes -Context "$Context"
            $toolExitCode = $LASTEXITCODE

            $capturedOutput = Get-Content -Path $tempOutputFile -Raw -Encoding utf8

            # Filter out misleading Gemini warnings about unreadable directories
            if ($ToolName -eq 'Gemini') {
                $capturedOutput = $capturedOutput -replace '(?m)^\s*\[WARN\]\s+Skipping unreadable directory:.*?\n', ''
            }
        }

        Write-PSFMessage -Level Verbose -Message "Tool exited with code: $toolExitCode"
        if ($toolExitCode -eq 0) {
            Write-PSFMessage -Level Verbose -Message "Successfully processed: $batchDesc"
        } else {
            Write-PSFMessage -Level Error -Message "Failed to process $batchDesc (exit code $toolExitCode)"
        }

    } finally {
        # Clean up temp file
        Remove-Item -Path $tempOutputFile -Force -ErrorAction SilentlyContinue
    }

    return @{
        Output   = $capturedOutput
        ExitCode = $toolExitCode
        Success  = ($toolExitCode -eq 0)
    }
}
