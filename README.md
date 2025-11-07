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

aitools wraps *agentic CLI tools* — AI assistants that actually read, understand, and rewrite your code — making them scriptable and repeatable through PowerShell. Every run starts clean—no conversation drift, just quality output.

**In 30 seconds:**

```powershell
# Install the module
Install-Module aitools

# Install Claude Code
Install-AITool -Name ClaudeCode

# Migrate all your Pester tests from v4 to v5
Get-ChildItem tests\*.Tests.ps1 | Update-PesterTest
```

That's it. aitools coordinates the AI, handles file I/O, tracks changes, and gives you PowerShell's predictability.

---

## Why aitools exists

The problem with AI coding assistants isn't their capability — it's their interface. Each CLI has different flags, installation steps, and quirks. When you need to process 100 files, you either:

1. Click through each one manually in an IDE
2. Write brittle shell scripts that break when the CLI changes
3. Build your own wrapper (what I did, then shared)

**aitools solves this by:**

- Providing one consistent interface across multiple AI CLIs
- Making batch operations simple: pipe files in, get results out
- Handling the boring parts (installation, updates, configuration)
- Tracking what changed for review before committing

**BUT ALSO**: Because aitools processes each file in a fresh, non-interactive session, the AI produces incredibly consistent, high-quality output without the context drift or degradation that happens in long interactive conversations.

---

## How it differs from API wrappers

You might wonder why this exists when [PSOpenAI](https://github.com/mkht/PSOpenAI) is available. The answer: they solve different problems.

| API Wrappers (like PSOpenAI)             | Agentic CLI Tools (like Claude Code)        |
| ---------------------------------------- | -------------------------------------------- |
| Send prompts, receive text               | Open files, understand code, make edits      |
| You handle file I/O and context          | Built-in file management and context         |
| Great for generating new content         | Great for refactoring existing code          |
| Requires scaffolding for code work       | Ships with full coding toolchain             |

PSOpenAI is excellent for what it does. aitools is for when you need an AI to *edit code*, not just *generate text*.

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
Install-AITool -Name ClaudeCode

# Or several
Install-AITool -Name Gemini, Aider

# Or all of them
Install-AITool -Name All
```

### Set your default tool

```powershell
Set-AIToolDefault -Tool ClaudeCode
```

Now any aitools command will use Claude Code unless you specify otherwise.

---

## Quick Start Examples

### Migrate test frameworks

```powershell
Get-ChildItem ./tests/*.Tests.ps1 | Update-PesterTest
```

This updates your Pester v4 tests to v5 syntax — handling BeforeAll/AfterAll blocks, Context/Describe changes, and parameter validation.

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

---

## Supported AI Tools

| Tool | Best For | Pricing | Status |
| --- | --- | --- | --- |
| **Claude Code** | Complex refactoring, best overall coder | Subscription | ✅ Supported |
| **Gemini CLI** | Large context windows, generous free tier | Free + paid | ✅ Supported |
| **Aider** | Reliable diffs, fast iteration | Free + paid | ✅ Supported |
| **GitHub Copilot** | Integration with GitHub workflow | Free + paid | ✅ Supported |
| **Codex CLI** | Fast processing | Subscription | ✅ Supported |
| **Cursor AI** | IDE integration | Free + paid | ✅ Supported |
| **Ollama** | Offline use, completely free | Free | ✅ Supported |

Each tool has different strengths. Claude Code is the strongest coder but can struggle with files over 400 lines. Gemini has massive context windows. Ollama runs locally with no API costs. Use what fits your needs.

---

## Core Concepts

### The Three-Step Process

Every aitools operation follows the same pattern:

1. **Input** — Provide files and a prompt
2. **Processing** — AI reads, understands, and edits
3. **Review** — You see diffs and decide to keep or discard

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
    Tool            = "ClaudeCode"
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
    Tool            = "ClaudeCode"
}
Invoke-AITool @params
```

This handles namespace changes, XML property renames, and layout differences — automatically refactoring the entire module.

### Case Study: Updating dbatools.io Blog

The [dbatools.io blog](https://dbatools.io) needed systematic updates: broken links, deprecated commands, outdated screenshots, and stale Twitter embeds. The challenge required judgment, not mechanical find-replace.

**The requirements:**

- Fix broken links but preserve historical context
- Remove Twitter/X embeds while keeping meaning
- Convert PowerShell screenshots to Hugo shortcodes
- Update deprecated command names
- Consider splatting for readability (but not blindly)
- Maintain author voice and historical accuracy

**The solution:**

```powershell
Set-AIToolDefault -Tool ClaudeCode
Get-ChildItem *.md | Invoke-AITool -Prompt ./prompts/audit-blog.md
```

Using a 300-line prompt that encoded all the nuance, Claude Code processed hundreds of posts, making judgment calls throughout:

- Tested and replaced dead links
- Converted Twitter embeds to paraphrased statements
- Extracted commands from screenshots and converted to shortcodes
- Applied splatting only where it improved clarity
- Updated deprecated references while preserving historical context

This demonstrates what agentic CLIs do well: read complex requirements, maintain context, and exercise judgment at scale.

---

## Advanced Usage

### Working with Images (Codex Only)

```powershell
$params = @{
    Tool       = 'Codex'
    Prompt     = 'Create a Hugo website using colors from this design'
    Attachment = '.\design.png'
}
Invoke-AITool @params
```

The `-Attachment` parameter works with image files (`.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.webp`, `.svg`) and is currently only supported by Codex.

### Custom Configuration

```powershell
# Set default model
Set-AIToolConfig -Tool ClaudeCode -Model claude-sonnet-4-5

# Update all installed tools
Update-AITool
```

### Processing Subsets

```powershell
# Skip the first 30 files, process the next 20
Get-ChildItem tests\*.Tests.ps1 |
  Update-PesterTest -First 20 -Skip 30 -Verbose
```

Useful for debugging prompts or resuming interrupted batches.

---

## Demo Walkthrough

The included Jupyter notebook (`demo.ipynb`) walks through migrating dbatools' 3,500+ Pester tests from v4 to v5. It shows:

1. **Setup** — Import module, configure defaults, prepare workspace
2. **Execution** — Open a real test file and run `Update-PesterTest`
3. **Review** — Examine structural changes, parameter updates, style enforcement

The demo achieves ~80% automation accuracy, with remaining fixes due to legacy code quality. It illustrates how aitools combines PowerShell's predictability with AI's flexible reasoning.

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