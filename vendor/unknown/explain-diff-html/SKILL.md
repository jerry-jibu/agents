---
name: explain-diff-html
description: Use when the user asks for a rich explanation of a code change, diff, branch, or PR. Produces HTML output.
---

# Explain Diff

Please make me a rich, interactive explanation of the specified code change.

It should have these sections:

- **Background**: Explain the existing system relevant to this change. (You should broadly explore surrounding code for this.) We don't know how much the reader already knows, so include a deep background for beginners (note that it can be skipped if the reader is already familiar), and then a more narrow background directly relevant to the change.
- **Intuition**: Explain the core intuition for the code change. The focus here is to explain the essence, not the full details. Use concrete examples with toy data. Use figures and diagrams liberally.
- **Code**: Do a high-level walkthrough of the changes to the code. Group/order the changes in an understandable way.
- **Quiz**: Come up with 5 medium-difficulty interactive multiple-choice questions to check the reader's understanding.

## Format

- Output a single self-contained HTML file with inline CSS and JS.
- One long page with section headers and a table of contents.
- Responsive layout (mobile-friendly).
- Save the file outside the repo: `/tmp/YYYY-MM-DD-explanation-<slug>.html`
- Writing style: Martin Kleppmann — clear, flowing prose with smooth transitions between ideas.
- Diagrams: use HTML-based designs only (no ASCII art); prefer simple box-and-arrow layouts, lists with borders, or system diagrams with example data rendered purely in HTML/CSS.
- Code blocks: always use `<pre>` tags with `white-space: pre` or `white-space: pre-wrap`.
- Use callout boxes for key concepts, edge cases, and definitions.
