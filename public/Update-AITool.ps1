function Update-AITool {
    <#
    .SYNOPSIS
        Updates the specified AI CLI tool(s) or all installed tools.

    .DESCRIPTION
        Updates AI CLI tools (Claude Code, Aider, Gemini CLI, GitHub Copilot CLI, or OpenAI Codex CLI)
        to their latest versions. If no tool name is specified, updates all currently installed tools.

    .PARAMETER Name
        The name of the AI tool to update. Valid values: ClaudeCode, Aider, Gemini, GitHubCopilot, Codex
        If not specified, all installed tools will be updated.

    .EXAMPLE
        Update-AITool -Name ClaudeCode
        Updates only Claude Code to the latest version and returns installation details.

    .EXAMPLE
        Update-AITool
        Updates all currently installed AI tools and returns details for each.

    .OUTPUTS
        AITools.UpdateResult
        An object (or array of objects) containing Name, OldVersion, Version, and Path of updated tools.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [Alias('Tool')]
        [string]$Name
    )

    begin {
        if ($Name) {
            Write-PSFMessage -Level Verbose -Message "Starting update of $Name"
        } else {
            Write-PSFMessage -Level Verbose -Message "Starting update of all installed AI tools"
        }
    }

    process {
        # Determine which tools to update
        $toolsToUpdate = @()

        if ($Name) {
            Write-Progress -Activity "Updating AI Tools" -Status "Validating tool name" -PercentComplete 10
            # Update specific tool
            if ($script:ToolDefinitions.ContainsKey($Name)) {
                $toolsToUpdate += $Name
            } else {
                Write-Progress -Activity "Updating AI Tools" -Completed
                Stop-PSFFunction -Message "Unknown tool: $Name" -EnableException $true
                return
            }
        } else {
            # Update all installed tools
            Write-Progress -Activity "Updating AI Tools" -Status "Scanning for installed tools" -PercentComplete 10
            Write-PSFMessage -Level Verbose -Message "Scanning for installed AI tools..."
            foreach ($toolName in $script:ToolDefinitions.Keys) {
                $tool = $script:ToolDefinitions[$toolName]
                if (Test-Command -Command $tool.Command) {
                    Write-PSFMessage -Level Verbose -Message "Found installed tool: $toolName"
                    $toolsToUpdate += $toolName
                }
            }

            if ($toolsToUpdate.Count -eq 0) {
                Write-Progress -Activity "Updating AI Tools" -Completed
                Write-PSFMessage -Level Warning -Message "No AI tools are currently installed."
                return
            }

            Write-PSFMessage -Level Verbose -Message "Found $($toolsToUpdate.Count) installed tool(s) to update"
        }

        # Update each tool and output directly to pipeline
        $currentTool = 0
        foreach ($toolName in $toolsToUpdate) {
            $currentTool++
            $percentComplete = [math]::Min(20 + (($currentTool / $toolsToUpdate.Count) * 70), 90)

            if ($PSCmdlet.ShouldProcess($toolName, "Update AI tool")) {
                Write-Progress -Activity "Updating AI Tools" -Status "Updating $toolName ($currentTool of $($toolsToUpdate.Count))" -PercentComplete $percentComplete
                Write-PSFMessage -Level Verbose -Message ""
                Write-PSFMessage -Level Verbose -Message "Updating $toolName..."
                try {
                    # Capture old version before updating
                    $tool = $script:ToolDefinitions[$toolName]
                    $oldVersion = $null
                    if (Test-Command -Command $tool.Command) {
                        # Get version differently for PowerShell modules vs CLIs
                        if ($tool.IsWrapper) {
                            $module = Get-Module -ListAvailable -Name $tool.Command | Sort-Object Version -Descending | Select-Object -First 1
                            if ($module) {
                                $oldVersion = $module.Version.ToString()
                            }
                        } else {
                            $oldVersion = & $tool.Command --version 2>&1 | Select-Object -First 1
                            $oldVersion = ($oldVersion -replace '^.*?(\d+\.\d+\.\d+).*$', '$1').Trim()
                        }
                        Write-PSFMessage -Level Verbose -Message "Current version: $oldVersion"
                    }

                    # Install/Update the tool (pass through SkipInitialization and suppress warnings)
                    $installResult = Install-AITool -Name $toolName -SkipInitialization -SuppressAlreadyInstalledWarning

                    # Output UpdateResult with old version
                    if ($installResult) {
                        [PSCustomObject]@{
                            PSTypeName = 'AITools.UpdateResult'
                            Name       = $installResult.Tool
                            OldVersion = if ($oldVersion) { $oldVersion.Trim() } else { 'N/A' }
                            Version    = $installResult.Version
                            Path       = $installResult.Path
                        }
                    }
                } catch {
                    Write-PSFMessage -Level Error -Message "Failed to update $toolName : $_"
                }
            }
        }

        if (-not $Name -and $toolsToUpdate.Count -gt 0) {
            Write-Progress -Activity "Updating AI Tools" -Status "Complete" -PercentComplete 100
            Write-PSFMessage -Level Verbose -Message ""
            Write-PSFMessage -Level Verbose -Message "Update process completed for $($toolsToUpdate.Count) tool(s)"
        }

        Write-Progress -Activity "Updating AI Tools" -Completed
    }
}
