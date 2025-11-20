function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a scriptblock with exponential backoff retry logic for transient errors.

    .DESCRIPTION
        Wraps execution of a scriptblock with automatic retry capability using exponential backoff.
        Only retries on transient/retryable errors such as:
        - Timeouts
        - Rate limits (429 Too Many Requests)
        - Server errors (500, 502, 503, 504)
        - Connection/network issues
        - Quota/usage limits
        - Service overload/capacity issues

        Non-retryable errors fail immediately without retry:
        - Configuration errors (NoneType, invalid configuration, missing configuration)
        - Authentication/credentials errors (unauthorized, invalid API key)
        - Invalid parameters/arguments (bad request, validation errors)
        - File/path not found errors
        - Permission denied

        Retries with delays of 2, 4, 8, 16, 32, 64 minutes until the cumulative delay would exceed
        the maximum total time (default 240 minutes / 4 hours).

    .PARAMETER ScriptBlock
        The scriptblock to execute. Should return output and set $LASTEXITCODE.

    .PARAMETER MaxTotalMinutes
        Maximum total time in minutes for all retry delays combined. Default is 240 (4 hours).

    .PARAMETER InitialDelayMinutes
        Initial delay in minutes for the first retry. Default is 2. Subsequent retries double this.

    .PARAMETER EnableRetry
        Switch to enable retry logic. If not specified, executes once without retry.

    .PARAMETER Context
        Descriptive context for logging (e.g., "Processing file.ps1 with Claude").

    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { & claude --version } -EnableRetry -Context "Testing Claude"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,

        [int]$MaxTotalMinutes = 240,  # 4 hours default

        [int]$InitialDelayMinutes = 2,

        [switch]$EnableRetry,

        [string]$Context = "Operation"
    )

    # If retry is not enabled, just execute once
    if (-not $EnableRetry) {
        Write-PSFMessage -Level Verbose -Message "Retry not enabled, executing once: $Context"
        return & $ScriptBlock
    }

    Write-PSFMessage -Level Verbose -Message "Starting retry-enabled execution: $Context (Max total delay: $MaxTotalMinutes minutes)"

    $attemptNumber = 1
    $cumulativeDelayMinutes = 0
    $startTime = Get-Date

    while ($true) {
        Write-PSFMessage -Level Verbose -Message "[$Context] Attempt $attemptNumber"

        # Execute the scriptblock and capture result
        $result = & $ScriptBlock
        $exitCode = $LASTEXITCODE

        # Check if successful (exit code 0)
        if ($exitCode -eq 0) {
            if ($attemptNumber -gt 1) {
                $totalElapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 2)
                Write-PSFMessage -Level Important -Message "[$Context] Attempt $attemptNumber SUCCEEDED after $cumulativeDelayMinutes minutes of retries (total elapsed: $totalElapsed minutes)"
            } else {
                Write-PSFMessage -Level Verbose -Message "[$Context] Attempt $attemptNumber succeeded on first try"
            }
            return $result
        }

        # Determine if error is retryable by examining the output
        $isRetryable = $false
        $errorReason = "unknown error"

        if ($result) {
            $resultText = $result | Out-String

            # First check for NON-retryable errors (configuration, authentication, invalid parameters)
            # These should fail fast without retry
            if ($resultText -match '(?i)(argument of type|NoneType|not iterable|invalid configuration|missing configuration)') {
                $isRetryable = $false
                $errorReason = "configuration error (argument/NoneType)"
            }
            elseif ($resultText -match '(?i)(authentication failed|unauthorized|invalid credentials|invalid api key|api key)') {
                $isRetryable = $false
                $errorReason = "authentication/credentials error"
            }
            elseif ($resultText -match '(?i)(invalid parameter|invalid argument|bad request|validation error)') {
                $isRetryable = $false
                $errorReason = "invalid parameter/argument"
            }
            elseif ($resultText -match '(?i)(file not found|path not found|directory not found)') {
                $isRetryable = $false
                $errorReason = "file/path not found"
            }
            # Check for common retryable error patterns
            elseif ($resultText -match '(?i)(timeout|timed out|time out)') {
                $isRetryable = $true
                $errorReason = "timeout"
            }
            elseif ($resultText -match '(?i)(429|too many requests|rate limit)') {
                $isRetryable = $true
                $errorReason = "rate limit"
            }
            elseif ($resultText -match '(?i)(500|502|503|504|internal server error|bad gateway|service unavailable|gateway timeout)') {
                $isRetryable = $true
                $errorReason = "server error"
            }
            elseif ($resultText -match '(?i)(connection|network|socket|refused|reset|unreachable)') {
                $isRetryable = $true
                $errorReason = "connection issue"
            }
            elseif ($resultText -match '(?i)(quota|usage limit|insufficient credits)') {
                $isRetryable = $true
                $errorReason = "quota/usage limit"
            }
            elseif ($resultText -match '(?i)(overloaded|capacity)') {
                $isRetryable = $true
                $errorReason = "service overload"
            }
        }

        # If error is not retryable, fail immediately
        if (-not $isRetryable) {
            $totalElapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 2)
            Write-PSFMessage -Level Error -Message "[$Context] Attempt $attemptNumber FAILED with exit code $exitCode (non-retryable error). Total elapsed: $totalElapsed minutes"
            Write-PSFMessage -Level Verbose -Message "[$Context] Error is not retryable (not a timeout, rate limit, server error, or connection issue). Failing immediately."

            # Send failed attempt output to debug log
            if ($result) {
                Write-PSFMessage -Level Debug -Message "[$Context] Failed attempt output:`n$resultText"
            }

            return $result
        }

        # Calculate next delay using exponential backoff: 2^n minutes where n is attempt number
        $nextDelayMinutes = $InitialDelayMinutes * [Math]::Pow(2, $attemptNumber - 1)

        # Check if adding this delay would exceed the max total time
        $projectedTotal = $cumulativeDelayMinutes + $nextDelayMinutes
        if ($projectedTotal -gt $MaxTotalMinutes) {
            $totalElapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 2)
            Write-PSFMessage -Level Error -Message "[$Context] Retry EXHAUSTED after $attemptNumber attempts and $cumulativeDelayMinutes minutes of delays (total elapsed: $totalElapsed minutes). Next retry delay of $nextDelayMinutes minutes would exceed maximum of $MaxTotalMinutes minutes."

            # Return the last result (failure) rather than throwing, to maintain compatibility
            return $result
        }

        # Log retry with detailed information
        $totalElapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 2)
        Write-PSFMessage -Level Warning -Message "[$Context] Attempt $attemptNumber FAILED with exit code $exitCode (retryable: $errorReason)"
        Write-PSFMessage -Level Important -Message "[$Context] Will retry in $nextDelayMinutes minutes (cumulative delay: $projectedTotal minutes, total elapsed: $totalElapsed minutes)"

        # Send failed attempt output to debug log
        if ($result) {
            Write-PSFMessage -Level Debug -Message "[$Context] Failed attempt $attemptNumber output:`n$resultText"
        }

        # Wait for the delay period
        $delaySeconds = $nextDelayMinutes * 60
        Write-PSFMessage -Level Verbose -Message "[$Context] Sleeping for $delaySeconds seconds ($nextDelayMinutes minutes)..."
        Start-Sleep -Seconds $delaySeconds

        # Update cumulative delay and increment attempt counter
        $cumulativeDelayMinutes = $projectedTotal
        $attemptNumber++

        Write-PSFMessage -Level Verbose -Message "[$Context] Retry $attemptNumber starting now (cumulative delay so far: $cumulativeDelayMinutes minutes)"
    }
}
