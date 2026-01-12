$script:ModuleRoot = $PSScriptRoot
$PSDefaultParameterValues["Import-Module:Verbose"] = $false

function Import-ModuleFile {
    <#
    .SYNOPSIS
        Loads files into the module on module import.

    .DESCRIPTION
        This helper function is used during module initialization.
        It should always be dotsourced itself, in order to proper function.

        This provides a central location to react to files being imported, if later desired

    .PARAMETER Path
        The path to the file to load

    .EXAMPLE
        PS C:\> . Import-ModuleFile -File $function.FullName

        Imports the file stored in $function according to import policy
    #>
    [CmdletBinding()]
    Param (
        [string]
        $Path
    )

    Write-PSFMessage -Level Verbose -Message "Importing module file: $Path"
    if ($doDotSource) { . $Path }
    else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($Path))), $null, $null) }
}

# Import all internal functions
$privateFunctions = Get-ChildItem "$ModuleRoot\private" -Filter "*.ps1" -Recurse -ErrorAction Ignore
foreach ($function in $privateFunctions) {
    . Import-ModuleFile -Path $function.FullName
}

# Import all public functions
$publicFunctions = Get-ChildItem "$ModuleRoot\public" -Filter "*.ps1" -Recurse -ErrorAction Ignore
foreach ($function in $publicFunctions) {
    . Import-ModuleFile -Path $function.FullName
}


# Tool name aliases for convenience (maps user-friendly names to canonical names)
$script:ToolAliases = @{
    # Claude aliases
    'Code'          = 'Claude'
    'ClaudeCode'    = 'Claude'

    # Gemini aliases
    'GoogleGemini'  = 'Gemini'

    # Codex aliases
    'OpenAICodex'   = 'Codex'

    # Copilot aliases
    'GitHubCopilot' = 'Copilot'
}

# Tool definitions with CLI command mappings
$script:ToolDefinitions = @{
    'Claude'       = @{
        Command           = 'claude'
        InstallCommands   = @{
            Windows = 'winget install --id=Anthropic.ClaudeCode -e --accept-source-agreements --accept-package-agreements'
            Linux   = 'curl -fsSL https://claude.ai/install.sh | bash'
            MacOS   = 'curl -fsSL https://claude.ai/install.sh | bash'
        }
        UninstallCommands = @{
            Windows = 'winget uninstall --id=Anthropic.ClaudeCode -e'
            Linux   = 'claude uninstall'
            MacOS   = 'claude uninstall'
        }
        TestCommand       = 'claude --version'
        InitCommand       = 'claude setup-token'
        PermissionFlag    = '--dangerously-skip-permissions'
        Verbose           = '--verbose'
        Debug             = '--debug'
        Priority          = 1
    }
    'Aider'            = @{
        Command           = 'aider'
        InstallCommands   = @{
            Windows = @('python -m pip install aider-install', 'aider-install')
            Linux   = 'pipx install aider-chat'
            MacOS   = 'pipx install aider-chat'
        }
        UninstallCommands = @{
            Windows = 'uv tool uninstall aider-chat'
            Linux   = 'pipx uninstall aider-chat'
            MacOS   = 'pipx uninstall aider-chat'
        }
        TestCommand       = 'aider --version'
        InitCommand       = 'API_KEY_CHECK'  # Special flag for API key verification
        PermissionFlag    = '--yes-always'
        Model             = @{
            Flag    = '--model'
            Default = 'anthropic/claude-3-7-sonnet-20250219'
        }
        EditModeMap       = @{
            Diff  = @('--edit-format', 'diff')
            Whole = @('--edit-format', 'whole')
        }
        Verbose           = '--verbose'
        Debug             = '--verbose'
        Priority          = 5
    }
    'Gemini'        = @{
        Command           = 'gemini'
        InstallCommands   = @{
            Windows = 'npm install -g @google/gemini-cli'
            Linux   = 'npm install -g @google/gemini-cli'
            MacOS   = 'brew install gemini-cli'
        }
        UninstallCommands = @{
            Windows = 'npm uninstall -g @google/gemini-cli'
            Linux   = 'npm uninstall -g @google/gemini-cli'
            MacOS   = 'brew uninstall gemini-cli'
        }
        TestCommand       = 'gemini --version'
        InitCommand       = 'gemini login'
        PermissionFlag    = '--yolo'
        Model             = @{
            Flag    = '--model'
            Alias   = '-m'
            Default = 'gemini-2.5-pro'
        }
        Verbose           = '-d'
        Debug             = '--debug'
        Priority          = 3
    }
    'Copilot' = @{
        Command           = 'copilot'
        InstallCommands   = @{
            Windows = 'npm install -g @github/copilot'
            Linux   = 'npm install -g @github/copilot'
            MacOS   = 'npm install -g @github/copilot'
        }
        UninstallCommands = @{
            Windows = 'npm uninstall -g @github/copilot'
            Linux   = 'npm uninstall -g @github/copilot'
            MacOS   = 'npm uninstall -g @github/copilot'
        }
        TestCommand       = 'copilot --version'
        InitCommand       = 'copilot'  # Standalone CLI - prompts for /login if needed
        PermissionFlag    = '--allow-all-tools'
        Model             = @{
            Flag    = '--model'
            Default = 'claude-sonnet-4.5'
        }
        Verbose           = '--log-level info'
        Debug             = '--log-level debug'
        Priority          = 4
    }
    'Codex'         = @{
        Command           = 'codex'
        InstallCommands   = @{
            Windows = 'npm install -g @openai/codex'
            Linux   = 'npm install -g @openai/codex'
            MacOS   = 'npm install -g @openai/codex'
        }
        UninstallCommands = @{
            Windows = 'npm uninstall -g @openai/codex'
            Linux   = 'npm uninstall -g @openai/codex'
            MacOS   = 'npm uninstall -g @openai/codex'
        }
        TestCommand       = 'codex --version'
        InitCommand       = 'codex login'
        PermissionFlag    = '--full-auto'
        Model             = @{
            Flag    = '--model'
            Default = 'o4-mini'
        }
        Verbose           = 'RUST_LOG=info'
        Debug             = 'RUST_LOG=debug'
        Priority          = 2
    }
    'Cursor' = @{
        Command           = 'cursor-agent'
        InstallCommands   = @{
            Windows = $null
            Linux   = 'curl https://cursor.com/install -fsS | bash'
            MacOS   = 'curl https://cursor.com/install -fsS | bash'
        }
        UninstallCommands = @{
            Windows = $null
            Linux   = $null
            MacOS   = $null
        }
        TestCommand       = 'cursor-agent --version'
        InitCommand       = 'cursor-agent login'
        PermissionFlag    = '--approve-mcps'
        Model             = @{
            Flag    = '--model'
            Default = 'gpt-5'
        }
        Verbose           = '-v'
        Debug             = $null
        Priority          = 6
    }
    'Ollama' = @{
        Command           = 'ollama'
        InstallCommands   = @{
            Windows = 'winget install ollama.ollama'
            Linux   = 'curl -fsSL https://ollama.com/install.sh | sh'
            MacOS   = 'brew install ollama'
        }
        UninstallCommands = @{
            Windows = 'winget uninstall --id=ollama.ollama -e'
            Linux   = $null
            MacOS   = 'brew uninstall ollama'
        }
        TestCommand       = 'ollama --version'
        InitCommand       = 'ollama serve'
        PermissionFlag    = $null
        Model             = @{
            Flag    = ''          # Ollama uses positional model name, not a flag
            Default = 'llama3.1'
        }
        Verbose           = '-v'
        Debug             = $null
        Priority          = 5
    }
    'PSOPenAI' = @{
        Command           = 'PSOpenAI'  # Module name, not a CLI command
        InstallCommands   = @{
            Windows = 'Install-Module -Name PSOpenAI -Scope CurrentUser -Force'
            Linux   = 'Install-Module -Name PSOpenAI -Scope CurrentUser -Force'
            MacOS   = 'Install-Module -Name PSOpenAI -Scope CurrentUser -Force'
        }
        UninstallCommands = @{
            Windows = 'Uninstall-Module -Name PSOpenAI -Force'
            Linux   = 'Uninstall-Module -Name PSOpenAI -Force'
            MacOS   = 'Uninstall-Module -Name PSOpenAI -Force'
        }
        TestCommand       = 'Get-Module -ListAvailable PSOpenAI'
        InitCommand       = 'API_KEY_CHECK'  # Special flag for API key verification
        PermissionFlag    = $null
        Model             = $null
        Verbose           = $null
        Debug             = $null
        Priority          = 7
        IsWrapper         = $true  # Flag to indicate this is a PowerShell module wrapper, not a CLI
    }
}

# Define TEPP scriptblock (use shorter alias names for autocomplete)
$teppScriptBlockParams = @{
    Name        = 'Tool'
    ScriptBlock = { 'All', 'Code', 'Copilot', 'Gemini', 'Codex', 'Aider', 'Cursor', 'Ollama', 'PSOPenAI' }
}
Register-PSFTeppScriptblock @teppScriptBlockParams

# Define common TEPP name
$teppName = 'Tool'

# Register argument completers for each set of commands
$installParams = @{
    Command   = 'Install-AITool', 'Initialize-AITool', 'Update-AITool', 'Uninstall-AITool'
    Parameter = 'Name'
    Name      = $teppName
}
Register-PSFTeppArgumentCompleter @installParams

$invokeParams = @{
    Command   = 'Invoke-AITool', 'Set-AIToolConfig', 'Set-AIToolDefault', 'Clear-AIToolConfig', 'Get-AIToolConfig', 'Get-AITool', 'Update-PesterTest'
    Parameter = 'Tool'
    Name      = $teppName
}
Register-PSFTeppArgumentCompleter @invokeParams

# Register TEPP for prompt file names
Register-PSFTeppScriptblock -Name PromptName -ScriptBlock {
    $promptsPath = Join-Path $script:ModuleRoot "prompts"
    if (Test-Path $promptsPath) {
        Get-ChildItem -Path $promptsPath -Filter "*.md" -File | ForEach-Object {
            $_.Name
        }
    }
}

Register-PSFTeppArgumentCompleter -Command Get-AITPrompt -Parameter Name -Name PromptName

$exportedFunctions = @(
    'Clear-AIToolConfig',
    'ConvertTo-AITImage',
    'Get-AITool',
    'Get-AIToolConfig',
    'Get-AITPrompt',
    'Initialize-AITool',
    'Install-AITool',
    'Invoke-AITool',
    'Select-UnmodifiedFile',
    'Set-AIToolConfig',
    'Set-AIToolDefault',
    'Test-GitFileModified',
    'Uninstall-AITool',
    'Update-AITool',
    'Update-PesterTest'
)

Export-ModuleMember -Function $exportedFunctions

# Auto-initialize default tool on module import
Initialize-AIToolDefault