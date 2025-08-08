function Get-AITPrompt {
    <#
    .SYNOPSIS
        Retrieves AI prompt templates from the module's prompts directory.

    .DESCRIPTION
        Gets all prompt template files from the AITools module's prompts directory.
        Returns objects with Name and Body properties, or just the raw content if -Raw is specified.

    .PARAMETER Name
        Optional. Specific prompt file name to retrieve. Supports wildcards.
        If not specified, returns all prompt files.

    .PARAMETER Raw
        Switch parameter. When specified, returns only the raw content of the prompt(s)
        instead of PSCustomObject with Name and Body properties.

    .EXAMPLE
        Get-AITPrompt

        Gets all prompt files as objects with Name and Body properties.

    .EXAMPLE
        Get-AITPrompt -Name "migration*"

        Gets prompt files matching the pattern "migration*".

    .EXAMPLE
        Get-AITPrompt -Name "style.md" -Raw

        Gets the raw content of the style.md prompt file.

    .EXAMPLE
        Get-AITPrompt -Raw

        Gets the raw content of all prompt files (useful for piping to other commands).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name = "*",
        [Parameter()]
        [switch]$Raw
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Get-AITPrompt with Name: $Name, Raw: $Raw"

        # Get the prompts directory path
        $promptsPath = Join-Path $script:ModuleRoot "prompts"
        Write-PSFMessage -Level Verbose -Message "Prompts directory: $promptsPath"

        if (-not (Test-Path $promptsPath)) {
            Write-PSFMessage -Level Error -Message "Prompts directory not found: $promptsPath"
            throw "Prompts directory not found: $promptsPath"
        }
    }

    process {
        try {
            # Get prompt files matching the pattern
            $promptFiles = Get-ChildItem -Path $promptsPath -File -ErrorAction Stop | Where-Object Name -match $Name
            Write-PSFMessage -Level Verbose -Message "Found $($promptFiles.Count) prompt file(s)"

            if ($promptFiles.Count -eq 0) {
                Write-PSFMessage -Level Warning -Message "No prompt files found matching pattern: $Name"
                return
            }

            foreach ($file in $promptFiles) {
                Write-PSFMessage -Level Debug -Message "Processing file: $($file.Name)"

                try {
                    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop

                    if ($Raw) {
                        # Return just the raw content
                        Write-Output $content
                    } else {
                        # Return PSCustomObject with Name and Body
                        # Remove .md extension and capitalize first letter
                        $displayName = $file.BaseName
                        $displayName = $displayName.Substring(0,1).ToUpper() + $displayName.Substring(1)

                        [PSCustomObject]@{
                            Name = $displayName
                            Body = $content
                            PSTypeName = 'AITools.Prompt'
                        }
                    }
                } catch {
                    Write-PSFMessage -Level Error -Message "Failed to read file $($file.Name): $($_.Exception.Message)"
                    throw "Failed to read file $($file.Name): $($_.Exception.Message)"
                }
            }
        } catch {
            Write-PSFMessage -Level Error -Message "Error retrieving prompt files: $($_.Exception.Message)"
            throw "Error retrieving prompt files: $($_.Exception.Message)"
        }
    }
}