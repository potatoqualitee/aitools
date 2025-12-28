---
applyTo: '**/*.md'
description: 'Markdown formatting standards'
---

# Markdown Style Guidelines

Consistent Markdown formatting for documentation files.

## Blank Lines

- Use single blank lines between sections and elements
- Never use multiple consecutive blank lines
- Headings and lists must have a blank line above and below

## Headings

- Use consistent heading levels (don't skip levels)
- Start with a single H1 (`#`) for the document title
- Use sentence case for headings

## Lists

- Use `-` for unordered lists
- Use `1.` for ordered lists (let markdown handle numbering)
- Use 2 spaces for nested list indentation

```markdown
Text before list.

- First item
- Second item
  - Nested item
  - Another nested item
- Third item

Text after list.
```

## Code Blocks

- Always specify language for fenced code blocks
- Ensure closing triple backticks are on their own line
- No trailing whitespace after closing backticks

```javascript
// JavaScript code here
```

```python
# Python code here
```

```bash
# Shell code here
```

## Inline Formatting

- Use `**bold**` for strong emphasis
- Use `*italic*` for light emphasis
- Use backticks for `code`, `filenames`, and `commands`
- Use backticks for keyboard shortcuts like `Ctrl+C`

## Links

- Use descriptive link text (not "click here")
- Use reference-style links for long URLs
- Use reference-style links when the same URL appears multiple times

```markdown
See the [official documentation][docs] for more details.
The [documentation][docs] covers advanced topics.

[docs]: https://example.com/documentation
```

## Line Length

- Wrap prose at 80-100 characters when practical
- Don't wrap tables - maintain table formatting
- Don't wrap URLs or code blocks

## File Structure

- End all files with exactly one newline character
- No trailing whitespace on any lines
- Use UTF-8 encoding

## Tables

- Align columns for readability in source
- Use header row separators
- Keep tables simple when possible

```markdown
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Value 1  | Value 2  | Value 3  |
| Value 4  | Value 5  | Value 6  |
```
