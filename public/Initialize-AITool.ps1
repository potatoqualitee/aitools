function Initialize-AITool {
    <#
    .SYNOPSIS
        Initializes and authenticates an AI CLI tool after installation.

    .DESCRIPTION
        Runs the initialization/authentication flow for AI tools. Different tools have different init processes:
        - ClaudeCode: Launches interactive mode where you run '/login' for OAuth authentication (requires Claude subscription)
        - Aider: Displays instructions for setting API keys via environment variables or .env files
        - Gemini: Launches interactive CLI which prompts for Google login (OAuth) or API key setup
        - GitHubCopilot: Launches standalone CLI which prompts for browser authentication if needed (does NOT require gh CLI)
        - Codex: Launches CLI which prompts for ChatGPT OAuth login or API key

    .PARAMETER Tool
        The name of the AI tool to initialize. Valid values: ClaudeCode, Aider, Gemini, GitHubCopilot, Codex

    .EXAMPLE
        Initialize-AITool -Tool ClaudeCode
        Launches Claude Code in interactive mode - type '/login' to authenticate.

    .EXAMPLE
        Initialize-AITool -Tool Aider
        Displays instructions for configuring Aider API keys.

    .OUTPUTS
        None. Runs interactive authentication flows or displays configuration instructions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('Name')]
        [string]$Tool
    )

    begin {
        Write-PSFMessage -Level Verbose -Message "Starting initialization of $Tool"
        $PSDefaultParameterValues['Write-PSFMessage:Level'] = 'Output'

        # Handle "All" tool selection
        $toolsToInitialize = @()
        if ($currentTool -eq 'All') {
            Write-PSFMessage -Level Verbose -Message "Tool is 'All' - will initialize all installed tools"
            $toolsToInitialize = $script:ToolDefinitions.GetEnumerator() |
                Where-Object { Test-Command -Command $_.Value.Command } |
                Sort-Object { $_.Value.Priority } |
                Select-Object -ExpandProperty Key
            Write-PSFMessage -Level Verbose -Message "Tools to initialize: $($toolsToInitialize -join ', ')"
        } else {
            $toolsToInitialize = @($Tool)
        }
    }

    process {
        foreach ($currentTool in $toolsToInitialize) {
            Write-PSFMessage -Level Verbose -Message "Retrieving tool definition for $currentTool"
            $toolDef = $script:ToolDefinitions[$currentTool]

            if (-not $toolDef) {
                Write-PSFMessage -Level Warning -Message "Unknown tool: $currentTool, skipping"
                continue
            }

            # Check if tool is installed
            Write-PSFMessage -Level Verbose -Message "Checking if $currentTool is installed"
            if (-not (Test-Command -Command $toolDef.Command)) {
                Write-PSFMessage -Level Warning -Message "$currentTool is not installed, skipping. Run: Install-AITool -Name $currentTool"
                continue
            }

        Write-PSFMessage -Level Verbose -Message "Init command type: $($toolDef.InitCommand)"

        # Special handling for API key-based tools
        if ($toolDef.InitCommand -eq 'API_KEY_CHECK') {
            Write-PSFMessage -Level Verbose -Message "Running API key check for $currentTool"

            # Different message files for different tools
            if ($currentTool -eq 'PSOPenAI') {
                Show-ModuleMessage -MessageName 'psopenai-api-key-info'

                # Check if API key is already configured
                $apiKey = $env:OPENAI_API_KEY
                if (-not $apiKey) {
                    $apiKey = $global:OPENAI_API_KEY
                }

                if ($apiKey) {
                    Write-PSFMessage -Message "✓ OpenAI API key is already configured!"
                } else {
                    Write-PSFMessage -Level Warning -Message "⚠ No OpenAI API key found. Please configure using one of the methods above."
                }
            } else {
                # Aider or other API key-based tools
                Show-ModuleMessage -MessageName 'aider-api-key-info'

                # Check if API key is already configured
                if (Test-AiderAPIKey) {
                    Write-PSFMessage -Message "✓ API key is already configured!"
                } else {
                    Write-PSFMessage -Level Warning -Message "⚠ No API key found. Please configure using one of the methods above."
                }
            }
            return
        }

        # Run interactive initialization for other tools
        if (-not $toolDef.InitCommand) {
            Write-PSFMessage -Level Warning -Message "No initialization command defined for $currentTool"
            return
        }

        Write-PSFMessage -Message "Running initialization for $currentTool..."
        Write-PSFMessage -Level Verbose -Message "Command: $($toolDef.InitCommand)"

        try {
            # Special handling for specific tools
            if ($currentTool -eq 'GitHubCopilot') {
                # GitHub Copilot CLI is standalone - does NOT require gh CLI
                Write-PSFMessage -Level Verbose -Message "Checking GitHub Copilot CLI availability..."
                $copilotCheck = & copilot --version 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-PSFMessage -Level Warning -Message "⚠ Copilot CLI not found. Install via: npm install -g @github/copilot"
                    return
                }

                Write-PSFMessage -Message "✓ GitHub Copilot CLI is installed!"
                Show-ModuleMessage -MessageName 'githubcopilot-init-prompt'
                Read-Host

                Invoke-Expression $toolDef.InitCommand
            }
            elseif ($currentTool -eq 'ClaudeCode') {
                Show-ModuleMessage -MessageName 'claudecode-init-prompt'
                Read-Host

                Invoke-Expression $toolDef.InitCommand
            }
            elseif ($currentTool -eq 'Gemini') {
                Show-ModuleMessage -MessageName 'gemini-init-prompt'
                Read-Host

                Invoke-Expression $toolDef.InitCommand
            }
            elseif ($currentTool -eq 'Codex') {
                Show-ModuleMessage -MessageName 'codex-init-prompt'
                Read-Host

                Invoke-Expression $toolDef.InitCommand
            }
            else {
                # For other tools, just run the init command
                Write-PSFMessage -Level Verbose -Message "Executing init command"
                Invoke-Expression $toolDef.InitCommand
            }

                Write-PSFMessage -Level Verbose -Message "Init command completed successfully"
                Write-PSFMessage -Message "✓ $currentTool initialization complete!"
            } catch {
                Write-PSFMessage -Level Warning -Message "Failed to initialize $currentTool : $_"
            }
        } # End of foreach ($currentTool in $toolsToInitialize)
    }
}