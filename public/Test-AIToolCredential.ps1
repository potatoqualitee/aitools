function Test-AIToolCredential {
    <#
    .SYNOPSIS
        Tests if credentials are configured and valid for an AI tool.

    .DESCRIPTION
        Checks if credentials exist and optionally validates them by making
        a test API call or CLI invocation.

    .PARAMETER Tool
        The AI tool to test credentials for (default: Claude).

    .PARAMETER Validate
        If specified, actually tests the credential by making a call to the service.
        Without this switch, only checks if credentials exist.

    .PARAMETER CredentialPath
        Optional path to a credential/config file.

    .EXAMPLE
        Test-AIToolCredential -Tool Claude

    .EXAMPLE
        Test-AIToolCredential -Tool Claude -Validate

    .OUTPUTS
        PSCustomObject with:
        - Configured: Boolean - credentials exist
        - Valid: Boolean - credentials work (only set if -Validate used)
        - Source: Where credentials were found
        - Message: Status message
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tool = 'Claude',

        [Parameter()]
        [switch]$Validate,

        [Parameter()]
        [string]$CredentialPath
    )

    $result = [PSCustomObject]@{
        Configured = $false
        Valid      = $null
        Source     = $null
        Message    = ""
    }

    # Get credentials
    $creds = Get-AIToolCredential -Tool $Tool -CredentialPath $CredentialPath

    $result.Configured = $creds.Configured
    $result.Source = $creds.Source

    if (-not $creds.Configured) {
        $result.Message = "$Tool credentials not configured"
        return $result
    }

    $result.Message = "$Tool credentials found in $($creds.Source)"

    # Validate credentials if requested
    if ($Validate) {
        Write-PSFMessage -Level Verbose -Message "Validating $Tool credentials..."

        # Set environment variables for the test
        foreach ($envVar in $creds.EnvironmentVariables.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($envVar.Key, $envVar.Value, 'Process')
        }

        try {
            switch ($Tool) {
                'Claude' {
                    # Test with a simple prompt
                    $testResult = & claude -p "Reply with exactly: OK" --output-format text 2>&1
                    $exitCode = $LASTEXITCODE

                    if ($exitCode -eq 0 -and $testResult -match 'OK') {
                        $result.Valid = $true
                        $result.Message = "$Tool credentials are valid and working"
                    }
                    else {
                        $result.Valid = $false
                        $result.Message = "$Tool credentials found but validation failed: $testResult"
                    }
                }
                'Gemini' {
                    # Test Gemini CLI
                    $testResult = & gemini -p "Reply with: OK" 2>&1
                    $exitCode = $LASTEXITCODE

                    if ($exitCode -eq 0) {
                        $result.Valid = $true
                        $result.Message = "$Tool credentials are valid and working"
                    }
                    else {
                        $result.Valid = $false
                        $result.Message = "$Tool credentials found but validation failed"
                    }
                }
                default {
                    $result.Valid = $null
                    $result.Message = "$Tool credentials found (validation not implemented for this tool)"
                }
            }
        }
        catch {
            $result.Valid = $false
            $result.Message = "$Tool credentials validation error: $($_.Exception.Message)"
        }
    }

    return $result
}
