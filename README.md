# aitools

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/aitools)](https://www.powershellgallery.com/packages/aitools)
[![Downloads](https://img.shields.io/powershellgallery/dt/aitools)](https://www.powershellgallery.com/packages/aitools)
[![GitHub Stars](https://img.shields.io/github/stars/potatoqualitee/aitools?style=social)](https://github.com/potatoqualitee/aitools)

<img align="left" src="https://raw.githubusercontent.com/potatoqualitee/aitools/main/logo.png" alt="aitools logo" width="96">

**Batch-process your code with AI CLI editors.**

aitools is a PowerShell module that wraps AI coding assistants like Claude Code, Aider, Gemini CLI, and GitHub Copilot CLI. It automates code refactoring, migrations, and documentation tasks by making these AI tools scriptable through PowerShell.

<br clear="left"/>

---

## What is aitools?

aitools wraps *agentic CLI tools* - AI assistants that actually read, understand, and rewrite your code - and makes them scriptable through PowerShell. Every run starts fresh with no conversation drift, just consistent output.

**In 30 seconds:**

```powershell
# Install the module
Install-Module aitools

# Install Claude
Install-AITool -Name Claude

# Migrate all your Pester tests from v4 to v5
Get-ChildItem tests\*.Tests.ps1 | Update-PesterTest
```

aitools handles the AI coordination, file I/O, and change tracking while giving you PowerShell's predictability.

---

## Why I built this

Each AI CLI has different flags, installation steps, and quirks. Processing 100 files means clicking through each one in an IDE or writing shell scripts that break when the CLI changes. I built a wrapper and figured I'd share it.

**What it does:**

- One consistent interface across multiple AI CLIs
- Simple batch operations: pipe files in, get results out
- Handles installation, updates, and configuration
- Tracks changes for review before committing

Each file is processed in a fresh session, which means consistent output without conversation drift. Parallel processing, automatic retry logic, and the ability to skip already-modified files make it practical for large-scale operations.

---

# Getting started

## Requirements

- PowerShell 3+ or later
- Windows, Linux, or macOS

## Install aitools

```powershell
Install-Module aitools -Scope CurrentUser
```

## Install AI tools

Pick the AI assistant you want:

```powershell
# Install one
Install-AITool -Name Claude

# Install a specific version
Install-AITool -Name Claude -Version 2.0.52

# Install a specific version and auto-remove other versions
Install-AITool -Name Aider -Version 0.45.0 -UninstallOtherVersions

# Or several tools
Install-AITool -Name Gemini, Aider

# Or all of them
Install-AITool -Name All
```

### Installation Scope (Linux)

By default, tools install to user-local directories (`CurrentUser` scope) without requiring elevated privileges. On Linux, you can optionally install system-wide:

```powershell
# User-local installation (default, no sudo required)
Install-AITool -Name Aider -Scope CurrentUser

# System-wide installation (requires sudo on Linux)
Install-AITool -Name Gemini -Scope LocalMachine
```

When using `-Scope LocalMachine` on Linux:
- You'll be prompted for your sudo password if needed
- Prerequisites (Node.js, pipx) are installed via apt-get
- Tools are available to all users on the system

On macOS, Homebrew handles installations without requiring sudo, so both scopes work without elevated privileges.

## Set your default

```powershell
Set-AIToolDefault -Tool Claude
```

Now any aitools command will use Claude unless you specify otherwise.

---

# Quick examples

## Migrate test frameworks

```powershell
Get-ChildItem ./tests/*.Tests.ps1 | Update-PesterTest
```

Updates your Pester v4 tests to v5 syntax, handling BeforeAll/AfterAll blocks, Context/Describe changes, and parameter validation.

## Add documentation

```powershell
Get-ChildItem ./public/*.ps1 |
  Invoke-AITool -Prompt "Add complete comment-based help with 3 examples"
```

## Enforce code style

```powershell
Get-ChildItem *.ps1 -Recurse |
  Invoke-AITool -Prompt "Apply One True Brace Style formatting"
```

## Compare multiple AI tools

```powershell
Invoke-AITool -Path ./script.ps1 -Prompt "Optimize this" -Tool All
```

Runs the same task through all installed AI tools and compares results.

## Choosing the right tool

```powershell
# Complex refactoring: Claude for deep understanding
Get-ChildItem src\*.ps1 | Invoke-AITool -Tool Claude -Prompt ./prompts/refactor-dependency-injection.md

# Large-scale refactoring: Gemini for massive context (entire codebase awareness)
Get-ChildItem src\*.ps1 | Invoke-AITool -Tool Gemini -Prompt ./prompts/modernize-ps7.md

# Quick metadata fixes: Copilot for speed
Get-ChildItem recipes\*.md | Invoke-AITool -Tool Copilot -Prompt ./prompts/fix-recipe-metadata.md

# T-SQL case sensitivity: Copilot for fast processing
Get-ChildItem sql\*.sql | Invoke-AITool -Tool Copilot -Prompt "Convert all keywords to uppercase"

# Blog updates: Copilot for rapid content corrections
Get-ChildItem blog\*.md | Invoke-AITool -Tool Copilot -Prompt ./prompts/update-blog-links.md
```

---

# Supported AI Tools

| Tool | Best For | Pricing | Status |
| --- | --- | --- | --- |
| **Claude** | Complex refactoring, architectural changes | Subscription | ✅ Supported |
| **Gemini CLI** | Massive context (1M tokens), multimodal | Free + paid | ✅ Supported |
| **Copilot** | Fast tasks, blog updates, GitHub workflow | Free + paid | ✅ Supported |
| **Aider** | Reliable diffs, fast iteration | Free + paid | ✅ Supported |
| **Codex CLI** | Fast processing, vision support | Subscription | ✅ Supported |
| **Cursor AI** | IDE integration | Free + paid | ✅ Supported |
| **Ollama** | Offline use, completely free | Free | ✅ Supported |
| **PSOpenAI** | Image/video/audio generation | Pay-per-use | ✅ Supported |

## Which one to use

- **Claude** excels at complex refactoring and architectural changes where deep code understanding is critical, but can struggle with files over 400 lines
- **Gemini 3** handles complex refactoring with a massive 1 million-token context window, allowing you to process entire large codebases in one session. Strong at multimodal understanding (code, images, video, audio) and offers a generous free tier
- **Copilot** shines for fast, focused tasks like blog updates, T-SQL case conversion, metadata fixes, or quick content corrections
- **Ollama** runs completely offline with no API costs

> **Note:** PSOpenAI is a PowerShell module wrapper (not a CLI), providing capabilities that agentic tools don't yet support like image editing, video generation, and text-to-speech.

> **Tool Name Change:** As of v1.0.5, `ClaudeCode` has been renamed to `Claude` and `GitHubCopilot` to `Copilot` for simplicity. The old names still work as aliases for backward compatibility.

## How it differs from API wrappers

Most of aitools wraps *agentic CLI tools* - AI assistants that read, understand, and rewrite code - but it also includes [PSOpenAI](https://github.com/mkht/PSOpenAI) for image/video/audio generation and editing.

| API Wrappers (like PSOpenAI)             | Agentic CLI Tools (like Claude Code)        |
| ---------------------------------------- | -------------------------------------------- |
| Send prompts, receive text/media         | Open files, understand code, make edits      |
| You handle file I/O and context          | Built-in file management and context         |
| Great for generating new content         | Great for refactoring existing code          |
| Excels at image/video/audio generation   | Specialized for code editing workflows       |

PSOpenAI support is included for image editing and generation capabilities that CLI tools don't yet provide.

---

# How it works

## The three-step process

Every aitools operation follows the same pattern:

1. **Input** - Provide files and a prompt
2. **Processing** - AI reads, understands, and edits
3. **Review** - You see diffs and decide to keep or discard

This mirrors manual code review but scales to hundreds of files.

## Prompts and context

You can provide:

- **Inline prompts**: Quick instructions right in the command
- **Prompt files**: Reusable `.md` files with detailed instructions
- **Context files**: Reference docs, style guides, API specifications

Example with all three:

```powershell
$params = @{
    Path            = "./src/*.ps1"
    PromptFilePath  = "./prompts/api-migration.md"
    ContextFilePath = @(
        "./docs/new-api-spec.md",
        "./docs/style-guide.md"
    )
    Tool            = "Claude"
}
Invoke-AITool @params
```

The AI reads the prompt for what to do, the context for how to do it, and processes each file accordingly.

---

# Real-World Examples

## Case Study: Modernizing a Windows Module

The [BurntToast](https://github.com/Windos/BurntToast) module wraps Windows notification APIs. When Microsoft updated from Windows 10 to Windows 11 APIs, the module needed refactoring across multiple files.

```powershell
$params = @{
    Path            = "./burnttoast/*.ps1"
    PromptFilePath  = "./prompts/api-upgrade.md"
    ContextFilePath = @(
        "./docs/windows11-toast-sdk.md",
        "./docs/styleguide.md"
    )
    Tool            = "Claude"
}
Invoke-AITool @params
```

This handled namespace changes, XML property renames, and layout differences, automatically refactoring the entire module.

## Case Study: Updating dbatools.io Blog

The [dbatools.io blog](https://dbatools.io) needed systematic updates to fix broken links, deprecated commands, outdated screenshots, and stale Twitter embeds. This required judgment, not mechanical find-replace.

**Requirements:**

- Fix broken links but preserve historical context
- Remove Twitter/X embeds while keeping meaning
- Convert PowerShell screenshots to Hugo shortcodes
- Update deprecated command names
- Consider splatting for readability (but not blindly)
- Maintain author voice and historical accuracy

**Solution:**

```powershell
Set-AIToolDefault -Tool Claude
Get-ChildItem *.md | Invoke-AITool -Prompt ./prompts/audit-blog.md
```

Using a 300-line prompt that encoded all the nuance, Claude processed hundreds of posts, making judgment calls throughout:

- Tested and replaced dead links
- Converted Twitter embeds to paraphrased statements
- Extracted commands from screenshots and converted to shortcodes
- Applied splatting only where it improved clarity
- Updated deprecated references while preserving historical context

This demonstrates what agentic CLIs do well: read complex requirements, maintain context, and exercise judgment at scale.

---

## Advanced Usage

### Working with Images

**Image Analysis and Code Generation (Codex, Claude, Gemini)**

Vision-capable tools can analyze images and generate code based on visual input:

```powershell
# Using the -Attachment parameter
Invoke-AITool -Tool Codex -Attachment design.png -Prompt "Create a Hugo website using colors from this design"

# Piping image files directly (Codex treats them as attachments)
Get-ChildItem screenshot.png | Invoke-AITool -Tool Codex -Prompt "What UI framework was used?"

# Other tools treat piped images as regular files for analysis
Get-ChildItem diagram.png | Invoke-AITool -Tool Claude -Prompt "Describe this architecture"
```

The `-Attachment` parameter works with common image formats (PNG, JPG, GIF, etc.). Codex automatically treats piped image files as attachments, while other vision-capable tools analyze them as regular files.

**Image Editing and Generation (PSOpenAI)**

PSOpenAI provides direct image manipulation capabilities that CLI tools don't yet support:

```powershell
# Install and configure PSOpenAI
Install-AITool -Name PSOPenAI
Initialize-AITool -Tool PSOPenAI
$env:OPENAI_API_KEY = 'sk-your-api-key'

# Edit an existing image
Get-ChildItem C:\images\photo.png |
  Invoke-AITool -Tool PSOPenAI -Prompt "remove the background and add a white sticker border. make transparent. save with descriptive name"

# Generate a new image from text
Invoke-AITool -Tool PSOPenAI -Prompt "A serene mountain landscape at sunset"
```

**Key Differences:**
- **Codex** (and other CLI tools with vision): Analyze images and write code/scripts to manipulate them
- **PSOpenAI**: Directly edit or generate images through OpenAI's image API endpoints

**Authentication:** PSOpenAI requires an OpenAI API key. Set `$env:OPENAI_API_KEY` or run `Initialize-AITool -Tool PSOPenAI` for configuration instructions.

### Extended Thinking / Reasoning

Enable deeper reasoning for supported models (Claude, Aider, Codex, Cursor):

```powershell
# Claude: triggers extended thinking tokens
Invoke-AITool -Path complex.ps1 -Tool Claude -ReasoningEffort high

# Codex: uses OpenAI's o1/o3 reasoning models
Invoke-AITool -Path complex.ps1 -Tool Codex -ReasoningEffort medium

# Aider: enables reasoning-capable models
Invoke-AITool -Path complex.ps1 -Tool Aider -ReasoningEffort low
```

Reasoning effort levels: `low`, `medium`, `high`. Best for complex refactoring or architectural changes.

### Custom Configuration

```powershell
# Set default model
Set-AIToolConfig -Tool Claude -Model claude-sonnet-4-5

# Set default reasoning effort
Set-AIToolConfig -Tool Claude -ReasoningEffort medium

# Configure Aider output directory (defaults to temp directory)
Set-AIToolConfig -Tool Aider -AiderOutputDir "C:\MyAiderHistory"

# Update all installed tools
Update-AITool
```

**Aider Output Configuration**

By default, Aider generates history and metadata files (`.aider.input.history`, `.aider.chat.history.md`, `.aider.model.settings.yml`, `.aider.model.metadata.json`, `.aiderignore`, `.env`) in your current directory. aitools redirects these to a temporary directory that gets cleaned up automatically.

To preserve Aider's history and metadata files, configure a custom output directory:

```powershell
Set-AIToolConfig -Tool Aider -AiderOutputDir "C:\AiderHistory"
```

This keeps all Aider output files in one location instead of cluttering your working directories.

### Parallel Processing

By default, when processing 4 or more files, Invoke-AITool runs them in parallel with up to 3 concurrent threads:

```powershell
# Processes files in parallel (default for 4+ files)
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Add error handling"

# Force sequential processing
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Add error handling" -NoParallel

# Increase concurrency (may trigger API rate limits)
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Add error handling" -MaxThreads 5
```

Results stream as they complete, providing real-time feedback.

### Automatic Retry with Exponential Backoff

Transient errors (timeouts, rate limits, server errors) are automatically retried with delays of 2, 4, 8, 16, 32, 64 minutes until the cumulative delay exceeds 4 hours:

```powershell
# Default: automatic retry enabled
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Refactor code"

# Disable retry - fail immediately on error
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Refactor code" -DisableRetry

# Customize max retry time (1 hour instead of 4)
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Refactor code" -MaxRetryMinutes 60
```

### Skip Modified Files

Resume interrupted batch operations by skipping files that have already been changed:

```powershell
# Skip files with uncommitted, staged, or unpushed changes
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Add error handling" -SkipModified

# When on main branch, check last 10 commits for modified files
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Add error handling" -SkipModified -CommitDepth 10
```

Useful for resuming after hitting rate limits or fixing errors mid-batch.

### Processing Subsets

```powershell
# Process only the first 5 files
Get-ChildItem tests\*.Tests.ps1 | Invoke-AITool -Prompt "Fix bugs" -First 5

# Skip the first 2 files, process the next 3
Get-ChildItem tests\*.Tests.ps1 | Invoke-AITool -Prompt "Fix bugs" -Skip 2 -First 3

# Process only the last 3 files
Get-ChildItem tests\*.Tests.ps1 | Invoke-AITool -Prompt "Fix bugs" -Last 3
```

Useful for debugging prompts or testing on a subset before full batch processing.

### Rate Limiting

Add delays between file processing to spread API calls over time:

```powershell
# Wait 10 seconds between each file
Get-ChildItem src\*.ps1 | Invoke-AITool -Prompt "Add docs" -DelaySeconds 10
```

Helps manage credit usage or avoid aggressive API throttling.

---

## Demo Walkthrough

The included Jupyter notebook (`demo.ipynb`) walks through migrating dbatools' 3,500+ Pester tests from v4 to v5. It shows:

1. **Setup** - Import module, configure defaults, prepare workspace
2. **Execution** - Open a real test file and run `Update-PesterTest`
3. **Review** - Examine structural changes, parameter updates, style enforcement

The demo achieves ~80% automation accuracy, with remaining fixes needed due to legacy code quality. It illustrates how aitools combines PowerShell's predictability with AI's flexible reasoning.

---

## Contributing

Pull requests are welcome. Please ensure:

- Code follows PowerShell best practices
- All parameter passing uses splatting
- Functions include complete comment-based help
- Changes are tested on Windows, Linux, and macOS
- New tools follow the existing `$ToolDefinitions` pattern

---

## Support

- **Issues**: [GitHub Issues](https://github.com/potatoqualitee/aitools/issues)
- **Module Gallery**: [PowerShell Gallery](https://www.powershellgallery.com/packages/aitools)