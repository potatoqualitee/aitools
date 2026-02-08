function Get-AITool {
    <#
    .SYNOPSIS
        Retrieves information about installed AI CLI tools.

    .DESCRIPTION
        Displays information about AI CLI tools including their installation status,
        version, and command path. By default, shows all available tools.

    .PARAMETER Tool
        The specific AI tool to check. If not specified, shows information for all tools.
        Valid values: All, Claude, Aider, Gemini, Copilot, Codex, Cursor, Ollama

    .EXAMPLE
        Get-AITool
        Shows information for all AI tools

    .EXAMPLE
        Get-AITool -Tool Claude
        Shows information only for Claude Code

    .EXAMPLE
        Get-AITool -Tool Aider
        Shows information only for Aider

    .OUTPUTS
        AITools.ToolInfo
        An object containing Tool name, Installed status, Version, and Path.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Tool = 'All'
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting Get-AITool for: $Tool"

        # Determine which tools to check
        $toolsToCheck = @()
        if ($Tool -eq 'All' -or $Tool -eq '*' -or [string]::IsNullOrWhiteSpace($Tool)) {
            Write-PSFMessage -Level Verbose -Message "Checking all available tools"
            $toolsToCheck = $script:ToolDefinitions.Keys | Sort-Object { $script:ToolDefinitions[$_].Priority }
        } else {
            Write-PSFMessage -Level Verbose -Message "Checking specific tool: $Tool"
            # Resolve tool alias to canonical name
            $resolvedTool = Resolve-ToolAlias -ToolName $Tool
            Write-PSFMessage -Level Verbose -Message "Resolved tool name: $resolvedTool"
            $toolsToCheck = @($resolvedTool)
        }
    }

    process {
        foreach ($currentToolName in $toolsToCheck) {
            Write-PSFMessage -Level Verbose -Message "Retrieving information for $currentToolName"

            # Get the tool definition
            $toolDef = $script:ToolDefinitions[$currentToolName]

            if (-not $toolDef) {
                Write-PSFMessage -Level Warning -Message "Unknown tool: $currentToolName"
                continue
            }

            # Check if the tool is installed
            $isInstalled = Test-Command -Command $toolDef.Command

            if ($isInstalled) {
                Write-PSFMessage -Level Verbose -Message "$currentToolName is installed"

                # Get version information differently for PowerShell modules vs CLIs
                try {
                    if ($toolDef['IsWrapper']) {
                        $module = Get-Module -ListAvailable -Name $toolDef.Command | Sort-Object Version -Descending | Select-Object -First 1
                        $version = $module.Version.ToString()
                        $commandPath = $module.Path
                    } else {
                        $versionOutput = & $toolDef.Command --version 2>&1 | Select-Object -First 1
                        $version = ($versionOutput -replace '^.*?(\d+\.\d+\.\d+).*$', '$1').Trim()

                        # If regex didn't match properly, use the original output
                        if ([string]::IsNullOrWhiteSpace($version) -or $version -eq $versionOutput) {
                            $version = $versionOutput.ToString().Trim()
                        }

                        # Get the command path
                        $commandInfo = Get-Command $toolDef.Command -ErrorAction SilentlyContinue
                        $commandPath = if ($commandInfo) { $commandInfo.Source } else { $null }
                    }

                    Write-PSFMessage -Level Verbose -Message "Version: $version"
                } catch {
                    $version = 'Unknown'
                    $commandPath = 'Unknown'
                    Write-PSFMessage -Level Verbose -Message "Failed to retrieve version: $_"
                }

                # Note: commandPath already set above, removed duplicate try block
                try {
                    Write-PSFMessage -Level Verbose -Message "Path: $commandPath"
                } catch {
                    $commandPath = 'Unknown'
                    Write-PSFMessage -Level Verbose -Message "Failed to retrieve path: $_"
                }
            } else {
                Write-PSFMessage -Level Verbose -Message "$currentToolName is not installed"
                $version = 'N/A'
                $commandPath = 'N/A'
            }

            # Output the tool information
            [PSCustomObject]@{
                PSTypeName = 'AITools.ToolInfo'
                Tool       = $currentToolName
                Installed  = $isInstalled
                Version    = $version
                Path       = $commandPath
            }
        }
    }
}
