################################################################################
#
#   ██████╗ ███████╗███████╗████████╗███████╗██████╗     ██╗   ██╗██╗  ██╗
#   ██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗    ██║   ██║██║  ██║
#   ██████╔╝█████╗  ███████╗   ██║   █████╗  ██████╔╝    ██║   ██║███████║
#   ██╔═══╝ ██╔══╝  ╚════██║   ██║   ██╔══╝  ██╔══██╗    ╚██╗ ██╔╝╚════██║
#   ██║     ███████╗███████║   ██║   ███████╗██║  ██║     ╚████╔╝      ██║
#   ╚═╝     ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝      ╚═══╝       ╚═╝
#
#                                    ↓↓↓
#
#   ██████╗ ███████╗███████╗████████╗███████╗██████╗     ██╗   ██╗███████╗
#   ██╔══██╗██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗    ██║   ██║██╔════╝
#   ██████╔╝█████╗  ███████╗   ██║   █████╗  ██████╔╝    ██║   ██║███████╗
#   ██╔═══╝ ██╔══╝  ╚════██║   ██║   ██╔══╝  ██╔══██╗    ╚██╗ ██╔╝╚════██║
#   ██║     ███████╗███████║   ██║   ███████╗██║  ██║     ╚████╔╝ ███████║
#   ╚═╝     ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝      ╚═══╝  ╚══════╝
#
#   PSConf.EU 2025 - Chrissy LeMaire (@funbucket.dev)
#   Converting 3500+ Pester Tests from v4 to v5 Using AI
#
################################################################################

################################################################################
#
#   Setup and Configuration
#
################################################################################

# Since it's coming from my repo and not the Gallery
Import-Module ./aitools.psd1 -Force

# Set default params and create reusable function
$PSDefaultParameterValues["Update-PesterTest:Raw"] = $true
$PSDefaultParameterValues["Import-Module:Verbose"] = $false
$PSDefaultParameterValues["Start-Process:NoNewWindow"] = $true

# Create function to clear changes
function Clear-Modified {
   Start-Process git -ArgumentList @("-C", "../dbatools", "restore", ".")
}

################################################################################
#
#   Check out the 3 integral prompt files
#
#   📄 prompt.md
#   📄 migration.md
#   📄 style.md
#
#   Now let's see it in action..
#
################################################################################

# Show the BEFORE state - classic Pester v4
Start-Process code -ArgumentList ./prompts/prompt.md
Start-Process code -ArgumentList ./prompts/migration.md
Start-Process code -ArgumentList ./prompts/style.md


################################################################################
#
#   🧪 The actual test file
#
################################################################################

# Pick a medium-complexity test file
$testFile = "C:\github\dbatools\tests\Invoke-DbaDbShrink.Tests.ps1"

# Show the BEFORE state - classic Pester v4
Start-Process code -ArgumentList $testFile

################################################################################
#
#   🚀 Migrate with Claude Code
#
#   First, check out the command and the tests that couldn't make the cut
#
################################################################################

# 📄 Load up public/Update-PesterTest.
Start-Process explorer -ArgumentList C:\github\aitools\public

# 📁 Load up large files
Start-Process explorer -ArgumentList C:\github\dbatools\tests

################################################################################
#
#   🐎 Now execute
#
################################################################################

# Set Claude Code just in case
Set-AIToolDefault -Tool Claude

# Clear all changes in the dbatools repo
Clear-Modified

# Run Claude
Update-PesterTest -InputObject $testFile

################################################################################
#
#   Claude excelled at
#
#   ✅ Structural refactoring (BeforeAll/AfterAll)
#   ✅ Parameter test refactoring
#   ✅ Where-Object conversions
#   ✅ Hashtable alignment
#   ✅ Comment preservation
#
#   Claude wasn't as good at
#
#   ❌ Large files
#   ❌ While rare, instructions were sometimes missed
#   ❌ Variable scoping fixes
#
#   "I would say [Claude migrated] about 80 percent automatically,
#   10 percent classic manual search and replace and 10 percent hard
#   manual work. Most manual cases were because code was not good in
#   the first place." ~ Andreas Jordan, co-migrator
#
#   Upgrading to v6
#
#   1. Update migration.md with v5 → v6 changes
#   2. Update style.md if needed
#   3. Get-ChildItem *.Tests.ps1 | Update-PesterTest
#
################################################################################

################################################################################
#
#   ✨ Gemini
#
################################################################################

# Clear all changes in the dbatools repo
Clear-Modified

# Set Gemini for that free 1000
Set-AIToolDefault -Tool Gemini

# Run Gemini CLI
Get-ChildItem C:\github\dbatools\tests\*.Tests.ps1 |
   Update-PesterTest -First 1 -Skip 1 -Verbose

################################################################################
#
#   🧭 GitHub Copilot
#
################################################################################

# Requires subscription
Set-AIToolDefault -Tool Copilot

################################################################################
#
#   🧠 First with GPT-5
#
################################################################################

# Clear all changes in the dbatools repo
Clear-Modified

# Update reasoning effort for ...different.. results
Set-AIToolConfig -Tool Codex -ReasoningEffort high

# Run
Get-ChildItem C:\github\dbatools\tests\*DbaDbShrink*.Tests.ps1 |
   Update-PesterTest -First 1 -Model gpt-5

################################################################################
#
#   🧠 Now with Sonnet
#
################################################################################

# Clear all changes in the dbatools repo
Clear-Modified

Get-ChildItem C:\github\dbatools\tests\*DbaDbShrink*.Tests.ps1 |
   Update-PesterTest -First 1 -Model claude-sonnet-4.5

################################################################################
#
#   This is repeatable for other types of refactoring 🎉
#
#   🧪 Test frameworks (Jest → Vitest)
#   🔄 API upgrades (any v1 → v2)
#   🎨 Linting/style fixes
#   📝 Documentation updates
#   🌍 i18n sweeps
#   🧩 Dependency migrations
#
################################################################################
