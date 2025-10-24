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


# Tool definitions with CLI command mappings
$script:ToolDefinitions = @{
    'ClaudeCode'       = @{
        Command           = 'claude'
        InstallCommands   = @{
            Windows = 'winget install --id=Anthropic.ClaudeCode -e --accept-source-agreements --accept-package-agreements'
            Linux   = 'npm install -g @anthropic-ai/claude-code'
            MacOS   = 'npm install -g @anthropic-ai/claude-code'
        }
        UninstallCommands = @{
            Windows = 'winget uninstall --id=Anthropic.ClaudeCode -e --accept-source-agreements --accept-package-agreements'
            Linux   = 'npm uninstall -g @anthropic-ai/claude-code'
            MacOS   = 'npm uninstall -g @anthropic-ai/claude-code'
        }
        TestCommand       = 'claude --version'
        InitCommand       = 'claude setup-token'
        PermissionFlag    = '--dangerously-skip-permissions'
        Model             = @{
            Flag    = '--model'
            Default = 'claude-sonnet-4-5-20250929'
        }
        Verbose           = '--verbose'
        Debug             = '--debug'
        Priority          = 1
    }
    'Aider'            = @{
        Command           = 'aider'
        InstallCommands   = @{
            Windows = @('python -m pip install aider-install', 'aider-install')
            Linux   = @('python -m pip install aider-install', 'aider-install')
            MacOS   = @('python -m pip install aider-install', 'aider-install')
        }
        UninstallCommands = @{
            Windows = 'uv tool uninstall aider-chat'
            Linux   = 'uv tool uninstall aider-chat'
            MacOS   = 'uv tool uninstall aider-chat'
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
    'GitHubCopilot' = @{
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
            Windows = 'Write-Host "⚠️ Native Windows install not supported. Please use WSL or Linux/macOS."'
            Linux   = 'curl https://cursor.com/install -fsSL | bash'
            MacOS   = 'curl https://cursor.com/install -fsSL | bash'
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
            Windows = 'winget uninstall ollama.ollama'
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
}

# Define TEPP scriptblock
$teppScriptBlockParams = @{
    Name        = 'Tool'
    ScriptBlock = { 'All', 'Aider', 'Gemini', 'ClaudeCode', 'Codex', 'GitHubCopilot', 'Cursor', 'Ollama' }
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
    Command   = 'Invoke-AITool', 'Set-AIToolConfig', 'Set-AIToolDefault', 'Clear-AIToolConfig', 'Get-AIToolConfig', 'Update-PesterTest'
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
    'Install-AITool',
    'Initialize-AITool',
    'Invoke-AITool',
    'Set-AIToolConfig',
    'Set-AIToolDefault',
    'Clear-AIToolConfig',
    'Get-AIToolConfig',
    'Get-AITPrompt',
    'Update-AITool',
    'Update-PesterTest',
    'Uninstall-AITool'
)

Export-ModuleMember -Function $exportedFunctions

# Auto-initialize default tool on module import
Initialize-AIToolDefault