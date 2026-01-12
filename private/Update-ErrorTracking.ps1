function Update-ErrorTracking {
    <#
    .SYNOPSIS
        Tracks errors and determines if bail-out threshold has been reached.

    .DESCRIPTION
        Analyzes result text for error patterns and updates error counts.
        Token/credit errors are tracked separately with a lower threshold
        since they indicate account-wide issues.

    .PARAMETER ResultText
        The result text to analyze for error patterns.

    .PARAMETER Success
        Whether the operation was successful (exit code 0).

    .PARAMETER MaxErrors
        Maximum number of general errors before bailing out.

    .PARAMETER MaxTokenErrors
        Maximum number of token/credit errors before bailing out.

    .PARAMETER ErrorCount
        Reference to the current error count (will be updated).

    .PARAMETER TokenErrorCount
        Reference to the current token error count (will be updated).

    .OUTPUTS
        [hashtable] with keys:
        - ShouldBailOut: Boolean indicating if we should stop processing
        - IsTokenError: Boolean indicating if this was a token/credit error
        - ErrorCount: Updated error count
        - TokenErrorCount: Updated token error count

    .EXAMPLE
        $params = @{
            ResultText      = $output
            Success         = $false
            MaxErrors       = 10
            MaxTokenErrors  = 3
            ErrorCount      = [ref]$errorCount
            TokenErrorCount = [ref]$tokenCount
        }
        $tracking = Update-ErrorTracking @params
        if ($tracking.ShouldBailOut) {
            Write-Warning "Stopping due to too many errors"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ResultText,

        [Parameter(Mandatory)]
        [bool]$Success,

        [Parameter()]
        [int]$MaxErrors = 10,

        [Parameter()]
        [int]$MaxTokenErrors = 3,

        [Parameter(Mandatory)]
        [ref]$ErrorCount,

        [Parameter(Mandatory)]
        [ref]$TokenErrorCount
    )

    $shouldBailOut = $false
    $isTokenError = $false

    # Only track errors when operation failed
    if ($Success) {
        return @{
            ShouldBailOut   = $false
            IsTokenError    = $false
            ErrorCount      = $ErrorCount.Value
            TokenErrorCount = $TokenErrorCount.Value
        }
    }

    # Analyze result text for error type
    if ($ResultText -match '(?i)(token|credits?|exhausted|quota|usage.?limit|insufficient|billing|payment)') {
        $isTokenError = $true
        $TokenErrorCount.Value++
        Write-PSFMessage -Level Warning -Message "Token/credit error detected ($($TokenErrorCount.Value) of $MaxTokenErrors max)"

        if ($TokenErrorCount.Value -ge $MaxTokenErrors) {
            $shouldBailOut = $true
            Write-PSFMessage -Level Error -Message "BAILING OUT: Reached $MaxTokenErrors token/credit errors. Stopping all processing."
            Write-Warning "BAILING OUT: Reached $MaxTokenErrors token/credit errors. Remaining files will not be processed."
        }
    } else {
        $ErrorCount.Value++
        Write-PSFMessage -Level Warning -Message "Error detected ($($ErrorCount.Value) of $MaxErrors max)"

        if ($ErrorCount.Value -ge $MaxErrors) {
            $shouldBailOut = $true
            Write-PSFMessage -Level Error -Message "BAILING OUT: Reached $MaxErrors errors. Stopping all processing."
            Write-Warning "BAILING OUT: Reached $MaxErrors errors. Remaining files will not be processed."
        }
    }

    return @{
        ShouldBailOut   = $shouldBailOut
        IsTokenError    = $isTokenError
        ErrorCount      = $ErrorCount.Value
        TokenErrorCount = $TokenErrorCount.Value
    }
}
