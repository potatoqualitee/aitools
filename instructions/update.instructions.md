---
applyTo: '**/*'
description: 'Procedures for updating AI agent instructions from the centralized repository'
---

# Update Instructions for AI Agents

These instructions are self-contained for update procedures but assume familiarity with Git. For general workflow guidance, see agent-workflow.instructions.md.

## Version Pinning Configuration

Repositories can control which version of AIM to sync by creating an `aim.config.json` file in the repository root:

```json
{
  "version": "latest"
}
```

**Supported values:**
- `"latest"` - Always sync to the most recent release (default behavior if no config exists)
- `"0.2.0"` or `"v0.2.0"` - Pin to a specific version

## Update Procedure

When updating AI agent instructions in a repository that uses AIM, AI agents should:

1. **Determine target version**
   - Check if `aim.config.json` exists in the repository root
   - If it exists, read the `version` field to determine the target version
   - If it doesn't exist or version is `"latest"`, use the most recent release

2. **Clone the centralized instructions repository** from GitHub
   - Clone the repository: `git clone https://github.com/tablackburn/ai-agent-instruction-modules.git`
   - If targeting a specific version (not "latest"), checkout that tag: `git checkout v0.2.0`
   - Use `AGENTS.template.md` from the cloned repository, NOT `AGENTS.md`
   - The file `AGENTS.md` in the centralized repository is that repository's own implementation
   - The file `AGENTS.template.md` is the template for downstream repositories
   - **Remove the HTML comment block** at the top of the fetched template (the comment that starts with `<!-- THIS IS THE TEMPLATE FILE`)

3. **Summarize changes** between the current and target versions
   - Read the current version from the downstream repository's `AGENTS.md` header (e.g., "Template Version: 0.1.0")
   - Read `CHANGELOG.md` from the cloned upstream repository
   - Extract all version sections between the current version and the target version
   - Provide the user with a brief summary of what has changed, noting any breaking changes
   - If the current version equals the target version, inform the user they are already up to date

4. **Check for existing repository-specific content** in the current AGENTS.md file
5. **Preserve any "Repository-Specific" sections** from the existing file
6. **Update the sync date and template version** in the header
7. **Merge preserved content** back into the updated instructions
8. **Replace the AGENTS.md file** with the updated content
9. **Sync the instructions folder** by copying all files from the centralized repository's instructions directory to the local instructions directory, overwriting existing files EXCEPT repository-specific.instructions.md (never copy or overwrite that file - it is unique to each downstream repository)
10. **Perform structural validation** to ensure the downstream repository matches the upstream structure
11. **Clean up** - Remove the cloned repository folder to prevent confusion from nested Git repositories

## Handling Breaking Changes

When upstream structural changes occur (e.g., renamed files, moved directories, or removed components), AI agents should:

- Review the upstream changelog for any noted breaking changes or structural updates
- Clone the upstream repository and compare files between the current downstream version and the latest upstream version
- Prioritize matching the upstream structure exactly, even if it requires significant downstream reorganization
- Document any repository-specific customizations that conflict with upstream changes and resolve them by adapting to the new structure
- If a file is renamed upstream, rename the corresponding downstream file and update all references accordingly

## Sync Checklist

- [ ] Target version determined from `aim.config.json` (or defaulted to latest)
- [ ] Correct version/tag checked out from upstream repository
- [ ] Change summary provided to user (from CHANGELOG)
- [ ] AGENTS.md content fetched and updated from centralized repository
- [ ] Template version and sync date updated to current date
- [ ] Repository-specific sections preserved from existing file
- [ ] Instructions/ folder synced, overwriting existing files except repository-specific.instructions.md
- [ ] Structural validation completed: downstream file structure matches upstream
- [ ] Cloned repository folder cleaned up

## Content Preservation Rules

- Repository-specific sections (starting with "## Repository-Specific") should be preserved
- The file repository-specific.instructions.md must NEVER be copied from the centralized repository or overwritten during sync - it is unique to each downstream repository
- Template sync date should be updated to current date
- Template version should match the centralized repository version
- Provide user feedback when repository-specific content is found and preserved

## Validation Steps Post-Sync

1. List all files in the local instructions directory
2. Compare the list against the expected files from the centralized repository
3. Ensure all files from the centralized repository have been copied EXCEPT repository-specific.instructions.md
4. Verify that file names and structure match the upstream repository exactly
5. If any files are missing or structural mismatches exist, re-run the sync process

## After Update

The AI agent will have access to:

- Code quality and security guidelines
- Language-specific coding standards (PowerShell, etc.)
- Git workflow and GitHub CLI best practices
- Markdown formatting standards
- Repository-specific customizations

## Version Tracking

- **Current version**: Stored in `AGENTS.md` header as "Template Version: X.Y.Z"
- **Target version**: Configured in `aim.config.json` (or defaults to "latest")
- **Change history**: Available in upstream `CHANGELOG.md`, follows semantic versioning
- Use version pinning for stability in production repositories
- Use "latest" for repositories that want to stay current with upstream changes
