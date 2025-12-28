# Repository-Specific Instructions for aitools

This file contains instructions specific to the **aitools** PowerShell module repository.

## Repository Overview

aitools is a PowerShell module that wraps AI coding assistants (Claude Code, Aider, Gemini CLI, GitHub Copilot CLI, Codex CLI, Cursor, Ollama, PSOpenAI) for batch processing of code files. It provides unified commands and pipeline support for automating code refactoring, migrations, and documentation tasks.

## Project Structure

```text
aitools/
├── aitools.psd1          # Module manifest
├── aitools.psm1          # Module loader
├── aitools.format.ps1xml # Output formatting
├── public/               # Exported functions (FunctionsToExport)
├── private/              # Internal helper functions
├── Tests/                # Pester test files
├── sample/               # Sample test files and examples
├── prompts/              # Prompt templates (if present)
└── instructions/         # AI agent instructions (AIM)
```

## Dependencies

This module requires:

- **PSFramework** (>= 1.7.249) - Configuration and logging framework
- **Microsoft.PowerShell.ThreadJob** (>= 2.2.0) - Parallel processing support

When modifying code that uses PSFramework functions or ThreadJob, ensure these dependencies are respected.

## Coding Standards

### Function Organization

- **Public functions** go in `public/` and must be added to `FunctionsToExport` in `aitools.psd1`
- **Private functions** go in `private/` and are internal helpers only
- Follow the existing naming convention: `Verb-AITool*` for public functions

### Tool Definitions Pattern

When adding support for new AI tools, follow the existing `$ToolDefinitions` pattern used throughout the codebase. Each tool requires:

- Argument builder function in `private/New-*Argument.ps1`
- Entry in the tool definitions hashtable
- Installation support in `Install-AITool.ps1`

### Splatting Requirement

All parameter passing must use splatting. This is a strict requirement for this codebase:

```powershell
# Correct
$params = @{
    Path   = $filePath
    Prompt = $promptText
    Tool   = 'Claude'
}
Invoke-AITool @params

# Incorrect - do not use inline parameters for complex calls
Invoke-AITool -Path $filePath -Prompt $promptText -Tool Claude
```

### Comment-Based Help

All public functions must include complete comment-based help with:

- Synopsis
- Description
- Parameter descriptions
- At least 3 examples
- Notes section if applicable

## Testing Requirements

- Tests use **Pester v5** syntax
- Test files follow the pattern `*.Tests.ps1`
- Main test file is `Tests/aitools.Tests.ps1`
- Sample tests in `sample/` demonstrate AI tool output comparisons

When writing or modifying tests, ensure compatibility with:

- Windows PowerShell 5.1
- PowerShell 7+ on Windows, Linux, and macOS

## Version Management

- Module version is in `aitools.psd1` under `ModuleVersion`
- Update version when making changes that will be published
- The module is published to PowerShell Gallery

## Branch and Workflow

- Main branch: `main`
- Work directly on `main` for small fixes
- Use feature branches for significant changes
- No special PR template requirements

## Special Considerations

### Cross-Platform Compatibility

This module must work on:

- Windows (PowerShell 5.1 and 7+)
- Linux (PowerShell 7+)
- macOS (PowerShell 7+)

Use platform-agnostic paths and commands. The `Get-OperatingSystem` private function helps detect the current platform.

### AI Tool Aliases

The module supports backwards-compatible aliases:

- `ClaudeCode` → `Claude`
- `GitHubCopilot` → `Copilot`

When referencing tools in code or documentation, use the new short names but ensure the aliases continue to work.

### Configuration Storage

Tool configurations are stored using PSFramework's configuration system. When modifying configuration-related functions, maintain compatibility with existing stored configurations.
