# AITools PowerShell Module

A PowerShell module for managing and automating AI-powered code editing tools, with specialized support for migrating Pester tests from v4 to v5 format.

## Overview

AITools lets you batch process files with Claude Code, Aider, Gemini, GitHub Copilot, and OpenAI Codex using consistent PowerShell commands.

Unlike API wrappers that require you to write prompts and handle file operations yourself, these agentic CLI tools actually edit your code. They read files, make decisions, apply changes, and write them back. AITools gives you PowerShell-native batch processing, persistent configuration, and pipeline support for these agents so you can process hundreds of files with a single command.

## Quick Start

```powershell
# Install and configure
Install-AITool -Name Gemini    # Free: 1000 calls/day
Set-AIToolDefault -Tool Gemini

# Process files
Invoke-AITool -Prompt "Add error handling" -Path ./script.ps1
Get-ChildItem *.ps1 | Invoke-AITool -Prompt "Add help docs"

# Migrate Pester tests
Get-ChildItem tests\*.Tests.ps1 | Update-PesterTest
```

## Installation

```powershell
Install-Module aitools
Install-AITool -Name ClaudeCode  # or Aider, Gemini, GitHubCopilot, Codex
Set-AIToolDefault -AutoDetect
```

## Commands

### Install-AITool

Installs AI CLI tools with cross-platform support.

```powershell
Install-AITool ClaudeCode
Install-AITool -Name Aider -Verbose
```

### Initialize-AITool

Initializes and authenticates AI tools after installation.

```powershell
# Initialize Claude Code (runs setup-token)
Initialize-AITool -Tool ClaudeCode

# Initialize Aider (shows API key configuration instructions)
Initialize-AITool -Tool Aider

# Initialize Gemini (runs login flow)
Initialize-AITool -Tool Gemini
```

### Update-AITool

Updates AI tools to their latest versions.

```powershell
# Update a specific tool
Update-AITool -Name ClaudeCode

# Update all installed tools
Update-AITool
```

### Set-AIToolDefault

Sets the default AI tool to use when -Tool is not specified.

```powershell
# Manually set default tool
Set-AIToolDefault -Tool ClaudeCode

# Auto-detect and set first available tool
Set-AIToolDefault -AutoDetect
```

### Invoke-AITool

Processes files using AI tools with batch support or provides chat-only mode.

```powershell
# Basic file processing
$splatInvoke = @{
    Tool   = "Aider"
    Prompt = "Fix bugs"
    Path   = "./script.ps1"
}
Invoke-AITool @splatInvoke

# Chat mode (no files)
Invoke-AITool -Prompt "How do I implement error handling?"

# With context files
$splatInvoke = @{
    Tool    = "GitHubCopilot"
    Prompt  = "Follow style guide"
    Path    = "./script.ps1"
    Context = @("./STYLEGUIDE.md")
}
Invoke-AITool @splatInvoke

# With reasoning effort
$splatInvoke = @{
    Prompt          = "Optimize this algorithm"
    Path            = "./complex.ps1"
    Tool            = "Codex"
    ReasoningEffort = "high"
}
Invoke-AITool @splatInvoke

# Raw mode (for Jupyter notebooks or direct output)
Invoke-AITool -Prompt "Fix bugs" -Path "./script.ps1" -Raw

# Pipeline processing
$splatWhere = @{
    Property = "Name"
    Like     = "*Test*"
}
$splatInvoke = @{
    Prompt = "Update to Pester v5"
    Tool   = "ClaudeCode"
}
Get-ChildItem *.ps1 -Recurse |
    Where-Object @splatWhere |
    Invoke-AITool @splatInvoke
```

### Set-AIToolConfig

Manages persistent tool configuration.

```powershell
# Set model
Set-AIToolConfig -Tool ClaudeCode -Model claude-sonnet-4-5-20250929

# Enable auto-approve
Set-AIToolConfig -Tool Aider -PermissionBypass

# Set edit mode (Aider only)
Set-AIToolConfig -Tool Aider -EditMode Whole

# Set reasoning effort
Set-AIToolConfig -Tool Codex -ReasoningEffort high
```

### Update-PesterTest

Migrates Pester v4 tests to v5 format using AI tools.

```powershell
# Migrate test files
Get-ChildItem ./tests/*.Tests.ps1 | Update-PesterTest

# Limit number of files processed
Get-ChildItem ./tests/*.Tests.ps1 | Update-PesterTest -Limit 10

# Use custom prompts
$splatUpdate = @{
    InputObject     = "./tests/MyTest.ps1"
    PromptFilePath  = "./custom-prompt.md"
    ContextFilePath = "./examples.md"
}
Update-PesterTest @splatUpdate
```

## Real-World Examples

### Batch Update Documentation

```powershell
# Add help to all public functions
$splatInvoke = @{
    Tool   = "ClaudeCode"
    Prompt = "Add comprehensive comment-based help with examples"
}
Get-ChildItem ./public/*.ps1 | Invoke-AITool @splatInvoke

# Use prompt template
$prompt = Get-AITPrompt -Name "style.md" -Raw
Get-ChildItem ./public/*.ps1 | Invoke-AITool -Prompt $prompt
```

### Refactor Test Suite

```powershell
# Migrate all Pester tests under size limit
$splatWhere = @{
    Property = "Length"
    LT       = 500KB
}
$splatUpdate = @{
    Tool  = "Aider"
    Limit = 10
}
Get-ChildItem ./tests/*.Tests.ps1 |
    Where-Object @splatWhere |
    Update-PesterTest @splatUpdate
```

### Style Enforcement

```powershell
# Apply style guide to all scripts
$splatInvoke = @{
    Tool    = "Aider"
    Prompt  = "Apply OTBS formatting and remove trailing spaces"
    Context = @("./STYLEGUIDE.md")
}
Get-ChildItem *.ps1 -Recurse | Invoke-AITool @splatInvoke
```

### Custom Migration

```powershell
# Use custom prompt and multiple context files
$splatUpdate = @{
    InputObject     = "./tests/Get-DbaDatabase.Tests.ps1"
    PromptFilePath  = "./prompts/custom-prompt.md"
    ContextFilePath = @("./docs/style.md", "./examples/sample-test.ps1")
    Tool            = "ClaudeCode"
    Verbose         = $true
}
Update-PesterTest @splatUpdate
```

## Advanced Usage

### Process with All Tools

Run operations against all installed tools at once:

```powershell
# Install all tools
Install-AITool -Name All

# Configure all tools with same settings
Set-AIToolConfig -Tool All -PermissionBypass

# Compare results from all tools
Invoke-AITool -Path "script.ps1" -Prompt "Optimize this code" -Tool All
```

### Flexible Input Types

The module accepts various input types for prompts and context:

```powershell
# Prompt as string
Invoke-AITool -Prompt "Add error handling" -Path ./script.ps1

# Prompt as file path (auto-detected and read)
Invoke-AITool -Prompt "./prompts/style.md" -Path ./script.ps1

# Prompt as FileInfo object
$prompt = Get-ChildItem ./prompts/migration.md
Invoke-AITool -Prompt $prompt -Path ./script.ps1

# Context as array of file paths
$splatInvoke = @{
    Prompt  = "Follow these guidelines"
    Path    = "./script.ps1"
    Context = @("./STYLE.md", "./EXAMPLES.md")
}
Invoke-AITool @splatInvoke

# Context as FileInfo objects
$contextFiles = Get-ChildItem ./docs/*.md
Invoke-AITool -Prompt "Document this" -Path ./code.ps1 -Context $contextFiles
```

### Custom Tool Definitions

Add your own AI tools without modifying the module:

```powershell
# Add your custom tool definition
$script:ToolDefinitions['CustomTool'] = @{
    Command         = "customtool"
    InstallCommands = @{
        Windows = "winget install CustomTool"
        Linux   = "npm install -g customtool"
        MacOS   = "brew install customtool"
    }
    TestCommand     = "customtool --version"
    InitCommand     = "customtool login"
    PermissionFlag  = "--auto-approve"
    Model           = @{
        Flag    = "--model"
        Default = "default-model"
    }
    Verbose         = "--verbose"
    Debug           = "--debug"
    Priority        = 6
}

# The tool is now immediately available in all functions
Install-AITool -Name CustomTool
Set-AIToolDefault -Tool CustomTool
```

## Best Practices

1. **Start Small**: Test with a few files before batch processing
1. **Use Version Control**: Always commit before running AI modifications
1. **Review Changes**: Manually review AI-generated changes
1. **Context Files**: Provide style guides and examples for consistent results
1. **File Size Limits**: Set appropriate `MaxFileSize` to avoid timeout issues
1. **Permission Bypass**: Defaults to `$true` (enabled). Set to `$false` for a practically useless approval mode
1. **Chat Mode**: Use chat mode (no -Path) for exploratory questions and design discussions
1. **Reasoning Effort**: Use higher reasoning levels for complex architectural or algorithmic tasks

## Troubleshooting

### Tool Not Found
```powershell
# Verify installation
Install-AITool -Name ClaudeCode -Verbose

# Check if command exists
Get-Command -Name claude -ErrorAction SilentlyContinue

# Initialize tool after installation
Initialize-AITool -Tool ClaudeCode
```

### No Default Tool Set
```powershell
# Error: "No tool specified and no default tool configured"
# Solution: Set a default tool
Set-AIToolDefault -AutoDetect

# Or manually specify
Set-AIToolDefault -Tool ClaudeCode
```

### Configuration Issues
```powershell
# View current settings
Get-AIToolConfig -Tool ClaudeCode

# Reset configuration
Clear-AIToolConfig -Tool ClaudeCode
```

## Contributing

Contributions are welcome! Please ensure:

- Code follows PowerShell best practices
- **ALL parameter passing uses splatting**
- All functions include comment-based help
- Changes are tested on Windows, Linux, and macOS
- New tools can be added to `$ToolDefinitions` and are automatically available via dynamic parameter class mapping

## License

MIT
