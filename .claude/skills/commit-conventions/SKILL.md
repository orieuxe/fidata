---
name: commit-conventions
description: This project's commit message and branch naming rules. Use whenever creating a git commit or a git branch in this repo.
---

# Commit message rules

Format: `<type>(<scope>): <description>`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`

- Description under 50 characters
- Imperative mood ("add", not "added"/"adds")
- No trailing period
- Lowercase first word unless a proper noun
- If more context is needed, add a body after a blank line

Example: `feat(scraper): add monthly backfill command`

# Branch naming rules

Format: `<type>/<issue-number>-<short-description>`, kebab-case.

Types: `feature`, `bugfix`, `hotfix`, `release`, `support`

Example: `feature/123-add-dark-mode`
