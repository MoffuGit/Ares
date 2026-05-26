# Agent Instructions

When running shell commands, exclude the Chromium checkout/directory from searches, file discovery, and bulk operations unless the user explicitly asks to work inside it.

Prefer commands that ignore Chromium paths, for example:
- `rg --glob '!**/chromium/**' ...`
- `find . -path '*/chromium' -prune -o ...`
- `fd --exclude chromium ...`

Do not traverse or inspect `test/chromium/` or any directory named `chromium` by default.
