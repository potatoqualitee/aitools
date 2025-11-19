# aitools

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/aitools)](https://www.powershellgallery.com/packages/aitools)
[![Downloads](https://img.shields.io/powershellgallery/dt/aitools)](https://www.powershellgallery.com/packages/aitools)
[![GitHub Stars](https://img.shields.io/github/stars/potatoqualitee/aitools?style=social)](https://github.com/potatoqualitee/aitools)

<img align="left" src="https://raw.githubusercontent.com/potatoqualitee/aitools/main/logo.png" alt="aitools logo" width="96">

**Batch-process your code with popular AI CLI editors.**

aitools is a PowerShell module that lets you automate code refactoring, migrations, and documentation tasks using AI coding assistants like Claude Code, Aider, Gemini CLI, and GitHub Copilot CLI.

<br clear="left"/>

---

## What is aitools?

aitools wraps *agentic CLI tools* (AI assistants that actually read, understand, and rewrite your code), making them scriptable and repeatable through PowerShell. Every run starts clean, with no conversation drift, just consistent quality output.

**In 30 seconds:**

```powershell
# Install the module
Install-Module aitools

# Install Claude
Install-AITool -Name Claude

# Migrate all your Pester tests from v4 to v5
Get-ChildItem tests\*.Tests.ps1 | Update-PesterTest
```

That's it. aitools coordinates the AI, handles file I/O, tracks changes, and gives you PowerShell's predictability.

---

## Why aitools exists

The problem with AI coding assistants isn't their capability, it's their interface. Each CLI has different flags, installation steps, and quirks. When you need to process 100 files, you either:

1. Click through each one manually in an IDE
2. Write brittle shell scripts that break when the CLI changes
3. Build your own wrapper (what I did, then shared)

**aitools solves this by:**

- Providing one consistent interface across multiple AI CLIs
- Making batch operations simple: pipe files in, get results out
- Handling the boring parts (installation, updates, configuration)
- Tracking what changed for review before committing

**BUT ALSO**: Because aitools processes each file in a fresh, non-interactive session, the AI produces incredibly consistent, high-quality output without the context drift or degradation that happens in long interactive conversations. Recent enhancements like parallel processing, automatic retry logic, and the ability to skip already-modified files make batch operations faster and more resilient.

---

## How it differs from API wrappers

Most of aitools wraps *agentic CLI tools* (AI assistants that read, understand, and rewrite code), but it also supports [PSOpenAI](https://github.com/mkht/PSOpenAI), a PowerShell wrapper for specialized capabilities like image/video/audio generation and editing.

| API Wrappers (like PSOpenAI)             | Agentic CLI Tools (like Claude Code)        |
| ---------------------------------------- | -------------------------------------------- |
| Send prompts, receive text/media         | Open files, understand code, make edits      |
| You handle file I/O and context          | Built-in file management and context         |
| Great for generating new content         | Great for refactoring existing code          |
| Excels at image/video/audio generation   | Specialized for code editing workflows       |

aitools includes PSOpenAI support specifically for image editing and generation capabilities that CLI tools don't yet provide.

---

## Installation

### Requirements

- PowerShell 3+ or later
- Windows, Linux, or macOS

### Install aitools

```powershell
Install-Module aitools -Scope CurrentUser
```

### Install AI tools

Pick the AI assistant you want to use:

```powershell
# Install one
Install-AITool -Name Claude

# Or several
Install-AITool -Name Gemini, Aider

# Or all of them
Install-AITool -Name All
```

### Set your default tool

```powershell
Set-AIToolDefault -Tool Claude
```

Now any aitools command will use Claude unless you specify otherwise.

---

## Quick Start Examples

### Migrate test frameworks

```powershell
Get-ChildItem ./tests/*.Tests.ps1 | Update-PesterTest
```

This updates your Pester v4 tests to v5 syntax, handling BeforeAll/AfterAll blocks, Context/Describe changes, and parameter validation.

### Add documentation

```powershell
Get-ChildItem ./public/*.ps1 |
  Invoke-AITool -Prompt "Add complete comment-based help with 3 examples"
```

### Enforce code style

```powershell
Get-ChildItem *.ps1 -Recurse |
  Invoke-AITool -Prompt "Apply One True Brace Style formatting"
```

### Compare multiple AI tools

```powershell
Invoke-AITool -Path ./script.ps1 -Prompt "Optimize this" -Tool All
```

Run the same task through all installed AI tools and compare results.

### Choose the right tool for the job

```powershell
# Complex refactoring: Use Claude for deep understanding
Get-ChildItem src\*.ps1 | Invoke-AITool -Tool Claude -Prompt ./prompts/refactor-dependency-injection.md

# Large-scale refactoring: Use Gemini for massive context (entire codebase awareness)
Get-ChildItem src\*.ps1 | Invoke-AITool -Tool Gemini -Prompt ./prompts/modernize-ps7.md

# Quick metadata fixes: Use Copilot for speed
Get-ChildItem recipes\*.md | Invoke-AITool -Tool Copilot -Prompt ./prompts/fix-recipe-metadata.md

# T-SQL case sensitivity: Use Copilot for fast processing
Get-ChildItem sql\*.sql | Invoke-AITool -Tool Copilot -Prompt "Convert all keywords to uppercase"

# Blog updates: Use Copilot for rapid content corrections
Get-ChildItem blog\*.md | Invoke-AITool -Tool Copilot -Prompt ./prompts/update-blog-links.md
```

---

## Supported AI Tools

| Tool | Best For | Pricing | Status |
| --- | --- | --- | --- |
| **Claude** | Complex refactoring, architectural changes, sophisticated code transformations | Subscription | ✅ Supported |
| **Gemini CLI** | Complex refactoring with massive context (1M tokens), multimodal understanding, generous free tier | Free + paid | ✅ Supported |
| **Copilot** | Fast processing, quick tasks (blog updates, case fixes, metadata), GitHub workflow | Free + paid | ✅ Supported |
| **Aider** | Reliable diffs, fast iteration | Free + paid | ✅ Supported |
| **Codex CLI** | Fast processing, vision support | Subscription | ✅ Supported |
| **Cursor AI** | IDE integration | Free + paid | ✅ Supported |
| **Ollama** | Offline use, completely free | Free | ✅ Supported |
| **PSOpenAI** | Image/video/audio generation and editing | Pay-per-use | ✅ Supported |

**Choosing the right tool:**
- **Claude** excels at complex refactoring and architectural changes where deep code understanding is critical, but can struggle with files over 400 lines
- **Gemini 3** is exceptional for complex refactoring with its 1 million-token context window, allowing you to process entire large codebases in a single session. Strong at multimodal understanding (code, images, video, audio) and offers a generous free tier
- **Copilot** shines for fast, focused tasks like blog updates, T-SQL case sensitivity conversion, fixing metadata, or quick content corrections
- **Ollama** runs completely offline with no API costs

**Note:** PSOpenAI is a PowerShell module wrapper (not a CLI), providing capabilities that agentic tools don't yet support like image editing, video generation, and text-to-speech.

**Tool Name Change:** As of v1.0.5, `ClaudeCode` has been renamed to `Claude` and `GitHubCopilot` to `Copilot` for simplicity. The old names still work as aliases for backward compatibility.

---

## Core Concepts

### The Three-Step Process

Every aitools operation follows the same pattern:

1. **Input** - Provide files and a prompt
2. **Processing** - AI reads, understands, and edits
3. **Review** - You see diffs and decide to keep or discard

This mirrors manual code review but scales to hundreds of files.

### Prompts and Context

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

## Real-World Examples

### Case Study: Modernizing a Windows Module

The [BurntToast](https://github.com/Windos/BurntToast) module wraps Windows notification APIs. When Microsoft updated from Windows 10 to Windows 11 APIs, the module needed refactoring.

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

This handles namespace changes, XML property renames, and layout differences, automatically refactoring the entire module.

### Case Study: Updating dbatools.io Blog

The [dbatools.io blog](https://dbatools.io) needed systematic updates to fix broken links, deprecated commands, outdated screenshots, and stale Twitter embeds. The challenge required judgment, not mechanical find-replace.

**The requirements:**

- Fix broken links but preserve historical context
- Remove Twitter/X embeds while keeping meaning
- Convert PowerShell screenshots to Hugo shortcodes
- Update deprecated command names
- Consider splatting for readability (but not blindly)
- Maintain author voice and historical accuracy

**The solution:**

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

# Update all installed tools
Update-AITool
```

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