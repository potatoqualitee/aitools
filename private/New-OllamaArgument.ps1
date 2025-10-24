function New-OllamaArgument {
    [CmdletBinding()]
    param(
        [string]$TargetFile,
        [string]$Message,
        [string]$Model,
        [bool]$UsePermissionBypass,
        [ValidateSet('low', 'medium', 'high')]
        [string]$ReasoningEffort
    )

    Write-PSFMessage -Level Verbose -Message "Building Ollama arguments..."
    $arguments = @('run')

    # Add verbose flag if requested
    if ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) {
        Write-PSFMessage -Level Verbose -Message "Adding verbose flag"
        $arguments += '-v'
    }

    # Use model from parameter or default
    if ($Model) {
        Write-PSFMessage -Level Verbose -Message "Using model: $Model"
        $arguments += $Model
    } else {
        Write-PSFMessage -Level Verbose -Message "Using default model: llama3.1"
        $arguments += 'llama3.1'
    }

    # Build the prompt message
    if ($TargetFile) {
        Write-PSFMessage -Level Verbose -Message "Target file: $TargetFile"
        # Read the file content to include in the prompt
        try {
            $fileContent = Get-Content -Path $TargetFile -Raw -ErrorAction Stop
            if ($Message) {
                $fullMessage = "$Message`n`nFile content:`n`n$fileContent"
            } else {
                $fullMessage = "Analyze and improve this file:`n`n$fileContent"
            }
        } catch {
            Write-PSFMessage -Level Warning -Message "Could not read target file: $_"
            $fullMessage = $Message
        }
    } elseif ($Message) {
        Write-PSFMessage -Level Verbose -Message "Using provided message"
        $fullMessage = $Message
    } else {
        Write-PSFMessage -Level Warning -Message "No message or target file provided"
        $fullMessage = ""
    }

    # Add the prompt message
    if ($fullMessage) {
        Write-PSFMessage -Level Verbose -Message "Adding prompt message"
        $arguments += $fullMessage
    }

    Write-PSFMessage -Level Verbose -Message "Ollama arguments built: $($arguments -join ' ')"
    return $arguments
}
