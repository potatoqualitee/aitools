# aitools

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/aitools)](https://www.powershellgallery.com/packages/aitools)
[![Downloads](https://img.shields.io/powershellgallery/dt/aitools)](https://www.powershellgallery.com/packages/aitools)
[![GitHub Stars](https://img.shields.io/github/stars/potatoqualitee/aitools?style=social)](https://github.com/potatoqualitee/aitools)

<img align="left" src="https://raw.githubusercontent.com/potatoqualitee/aitools/main/logo.png" alt="aitools logo" width="96">

**Batch-process your code with popular AI CLI editors.**
aitools is a PowerShell module for managing and automating *agentic CLI tools* such as
[**Claude Code**](https://github.com/anthropics/claude-code), [**Aider**](https://github.com/Aider-AI/aider), [**Cursor**](https://www.cursor.com), [**Gemini CLI**](https://github.com/google-gemini/gemini-cli), [**GitHub Copilot CLI**](https://github.com/github/copilot-cli), and more.

Unlike API wrappers that just send prompts, these CLIs actually read, understand, and rewrite your code — and aitools wraps them to make them scriptable and repeatable.

---

## Table of Contents

* [Wrapper vs Agentic CLI Tools](#wrapper-vs-agentic-cli-tools)
* [Why aitools?](#why-aitools)
* [Supported CLIs](#supported-clis)
* [Execution Model](#execution-model)
* [Tool Reasoning Profiles](#tool-reasoning-profiles)
* [Quick Start](#quick-start)
* [Common Scenarios](#common-scenarios)
* [Installation](#installation)
* [Advanced Usage](#advanced-usage)
* [Demo Walkthrough](#demo-walkthrough)
* [Real-World Case Study: Updating dbatools.io Blog](#real-world-case-study-updating-dbatoolsio-blog)
* [Contributing](#contributing)
* [License](#license)

---

## Wrapper vs Agentic CLI Tools

You might be wondering why I published this when [PSOpenAI](https://github.com/mkht/PSOpenAI) exists. I love PSOpenAI — it's the best PowerShell wrapper for the OpenAI-compatible APIs.

But it's built for **API interaction**, not **code transformation**. When you use agentic tools like Claude Code or GitHub Copilot CLI, they come with toolkits built in whereas APIs are bare, as in they don't manage file I/O, diffs, and other editor behaviors.

| PSOpenAI                                  | Agentic CLI Tools                              |
| ----------------------------------------- | ---------------------------------------------- |
| API wrapper — you send a prompt, get text | Code editor — it opens, edits, and saves files |
| You handle file I/O, diffs, and context   | Built-in context, patching, and safety         |
| Great for one-off prompts and scripting   | Great for real-world refactors and migrations  |
| Requires workflow scaffolding             | Ships with full toolchain and local memory     |

aitools orchestrates those CLIs with PowerShell's predictability, discoverability and power.

---

## Why aitools?

The reason I built aitools is so that I wouldn't have to repeatedly type `claude --help` and `gemini --help` when I need to figure out how to do something in the CLI. I looked up those just once and documented the steps.

| Without aitools                           | With aitools                        |
| ----------------------------------------- | ----------------------------------- |
| Remember CLI flags and install steps      | `Install-AITool -Name ClaudeCode`   |
| Switch between five different CLIs        | One consistent PowerShell interface |
| Manually open each file and paste prompts | Batch process hundreds of files     |

💡 **Purpose:** aitools brings *agentic AI* into your automation stack. Refactor, migrate, document, and standardize codebases at scale using the same workflows that PowerShell admins and developers use.

---

## Supported CLIs

| CLI | Pricing | Status |
| --- | --- | --- |
| **Claude Code** | Subscription required | ✅ Supported |
| **Cursor AI** | Free tier available | ✅ Supported |
| **GitHub Copilot** | Free tier available | ✅ Supported |
| **Google Gemini** | Free tier available | ✅ Supported |
| **Aider** | Free & paid tiers | ✅ Supported |
| **Codex CLI** | Flat monthly rate | ✅ Supported |
| **Ollama** | Free & open source | ✅ Supported |

---

## Execution Model

Every aitools operation follows a predictable 3-step reasoning cycle:

1. **Reasoning step** — Pass prompt + migration + style context
2. **Diff & validation** — Track and display exact edits for review

Example:

```powershell
Set-AIToolDefault -Tool ClaudeCode
Get-ChildItem ./tests/*.Tests.ps1 | Update-PesterTest -First 20 -Skip 30 -Verbose
```

This mirrors how you'd reason through a codebase manually — observe, act, verify — but scaled across hundreds of files.

---

## Quick Start

```powershell
# Install the module
Install-Module aitools

# Install and set your favorite AI CLI
Install-AITool -Name ClaudeCode
Set-AIToolDefault -Tool ClaudeCode

# Migrate all your Pester v4 tests to v5
Get-ChildItem tests\*.Tests.ps1 | Update-PesterTest
```

✅ Supports: **Claude Code**, **Aider**, **Gemini CLI**, **GitHub Copilot CLI**, **Codex CLI**, and **Ollama**
🧠 Works on **Windows, Linux, and macOS**

---

## Common Scenarios

### 🧪 Test Framework Migrations

```powershell
Get-ChildItem ./tests/*.Tests.ps1 | Update-PesterTest
```

### 📚 Documentation Sweeps

```powershell
Get-ChildItem ./public/*.ps1 |
  Invoke-AITool -Prompt "Add complete comment-based help for each parameter. Include 3 working examples."
```

### 🎨 Style Enforcement

```powershell
# This is an ineffective prompt, shown only for demo purposes
# It's much better to give step by step what OTBS is
Get-ChildItem *.ps1 -Recurse |
  Invoke-AITool -Prompt "Apply OTBS formatting"
```

### 🖼️ Image-Driven Design (Codex Only)

```powershell
# Create a Hugo website with colors extracted from an image
$params = @{
    Tool       = 'Codex'
    Prompt     = 'Create a new markdown-driven Hugo website that uses the color scheme of the image attachment'
    Attachment = '.\design-inspiration.png'
}

Invoke-AITool @params
```

> **Note:** The `-Attachment` parameter only works with **Codex** and supports image files (`.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.webp`, `.svg`).

### ⚙️ SDK Upgrades (Example: BurntToast Module)

Modules like [**BurntToast**](https://github.com/Windos/BurntToast), which wrap native Windows SDKs, evolve as the underlying APIs change — for example, migrating from the **Windows 10 Notification** APIs to newer Windows 11 APIs.

```powershell
# Modernize BurntToast module code to the latest Windows 11 SDK
$splatUpgrade = @{
    Path            = "./burnttoast/*.ps1"
    PromptFilePath  = "./prompts/api-upgrade.md"
    ContextFilePath = @(
        "./docs/windows11-toast-sdk.md",   # Updated WinRT namespaces
        "./docs/styleguide.md"             # Internal PowerShell guidelines
    )
    Tool            = "ClaudeCode"
    Verbose         = $true
}
Invoke-AITool @splatUpgrade
```

This setup uses:

* **`PromptFilePath`** — main migration instructions (`api-upgrade.md`)
* **`ContextFilePath`** — SDK docs, XML schema examples, or layout specs

aitools passes all of this to the AI agent so it can reason about namespace changes,
XML property renames, and adaptive layout differences — and automatically refactor your module.

---

## Installation

```powershell
# PowerShell Gallery (Windows, Linux, macOS)
Install-Module aitools -Scope CurrentUser

# Then install your individual agentic tools
Install-AITool -Name Gemini
Install-AITool -Name Aider
Install-AITool -Name ClaudeCode

# Or all of them
Install-AITool -Name All
```

### Update all tools

```powershell
Update-AITool
```

---

## Advanced Usage

```powershell
# Run multiple tools for comparison
Invoke-AITool -Path ./script.ps1 -Prompt "Optimize this" -Tool All

# Configure defaults
Set-AIToolConfig -Tool ClaudeCode -Model claude-sonnet-4-5

# Custom prompt and context
Update-PesterTest -PromptFilePath ./prompts/v5migration.md -ContextFilePath ./style.md
```

---

## Tool Reasoning Profiles

Each supported CLI has distinct reasoning characteristics.

| Tool            | Strengths                                                                   | Limitations                      |
| --------------- | --------------------------------------------------------------------------- | -------------------------------- |
| **Claude Code** | BEST coder by far, flat monthly rate | Struggles with very large files (400+ lines)  |
| **Aider**       | Reliable deterministic diffs, fast iterative patches                        | APIs are expensive          |
| **Gemini CLI**  | Lots of free calls, second best coder, huge context                                 | APIs are expensive once you get past the free call limit     |
| **Copilot CLI** | Affordable                                     | Just released, basically an alpha CLI |
| **Codex CLI**   | Fast, flat monthly rate                                               | No idea why people like its coding     |
| **Ollama**      | Completely free, runs locally, no API key required, great for offline use  | Models vary in quality, slower than cloud-based solutions    |

aitools lets you combine them — even run all in comparison mode — for multi-agent reasoning. Or just make your preferred agent more accessible, like I do.

---

## Demo Walkthrough

The included Jupyter notebook (`demo.ipynb`) shows a real-world, reasoning-driven migration of **dbatools' 3,500+ Pester tests** from v4 to v5.
It demonstrates how aitools coordinates *agentic CLIs* through three stages of reasoning:

1. **Initialization** — import the module, set `$PSDefaultParameterValues`, and clear workspace diffs
2. **Observation & action** — open a real test file (`Invoke-DbaDbShrink.Tests.ps1`) and run `Update-PesterTest` via Claude Code
3. **Evaluation** — review structural refactors (BeforeAll/AfterAll), parameter tests, and style enforcement

It highlights how Claude achieved ~80% automation accuracy, with remaining fixes due to legacy code quality.
The notebook illustrates *how aitools thinks* — combining reproducible PowerShell automation with the flexible reasoning of modern AI tools.

---

## Real-World Case Study: Updating dbatools.io Blog

A concrete example of aitools' power came from updating the [dbatools.io blog](https://dbatools.io) — a technical blog with years of posts about SQL Server automation. The blog needed systematic updates: broken links, outdated Twitter embeds, deprecated commands, and old PowerShell screenshots that should be converted to a modern format.

### The Challenge

The task required **nuanced judgment**, not mechanical find-replace:

- Posts are historical documents capturing what was true at the time
- Updates should fix genuine problems (broken links, wrong info) not stylistic preferences
- Twitter/X content needed removal while preserving context
- PowerShell screenshots should be converted to a `{{< powershell-console >}}` Hugo shortcode
- Code examples with 4+ parameters should consider splatting (but only when appropriate)
- Links to deprecated dbatools commands needed updating
- Technical accuracy required understanding ongoing practices vs. historical facts

### The Solution

Using Claude Code through aitools, the blog was batch-processed with a comprehensive audit prompt. The prompt (detailed in context) encoded:

- **CONTEXT**: dbatools maintains backward compatibility (PS 3+, SQL Server 2000+), current year is 2025
- **IMPORTANT**: This task requires nuance — preserve author voice, historical context, and intentional simplifications
- **CHECK AND FIX**: Frontmatter updates, link validation, Twitter/X removal, code modernization, screenshot conversion
- **PRESERVE**: Original writing style, all T-SQL code, working code, historical perspective

### The Process

```powershell
# Set default tool
Set-AIToolDefault -Tool ClaudeCode

# Process blog posts with the audit prompt
Get-ChildItem *.md | Invoke-AITool -Prompt ./update-blog.md
```

### The Results

Claude Code processed each blog post, exercising judgment throughout:

- **Links**: Tested and replaced dead links, updated Microsoft Docs URLs to current paths
- **Twitter/X**: Removed embeds and converted to paraphrased statements ("Jeffrey Snover once noted that...")
- **Screenshots**: Extracted PowerShell commands/output from images and converted to the `{{< powershell-console >}}` shortcode format
- **Code**: Converted appropriate multi-parameter commands to splatting (skipping casual demos where splatting would reduce clarity)
- **Commands**: Updated deprecated references (e.g., `Connect-DbaSqlInstance` → `Connect-DbaInstance`)
- **Historical Content**: Preserved version numbers, download counts, and time-specific milestones as historical facts
- **Ongoing Practices**: Updated content about code signing, security processes, and team operations

### Key Insight

This wasn't a simple "update all the things" job. It required an AI agent that could:

- **Read and understand** a 300-line prompt with nested instructions and exceptions
- **Exercise judgment** about what to change vs. preserve
- **Maintain context** across hundreds of files
- **Make nuanced decisions** about when splatting improves readability vs. when it's overkill

This is exactly what *agentic CLIs* excel at — and what aitools makes scriptable and repeatable.

---

## Contributing

Pull requests are welcome!

- Code follows PowerShell best practices
- **ALL parameter passing uses splatting**
- All functions include comment-based help
- Changes are tested on Windows, Linux, and macOS
- New tools can be added to `$ToolDefinitions` and are automatically available via dynamic parameter class mapping

---