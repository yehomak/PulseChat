---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(bin/rubocop:*), Bash(bundle exec brakeman:*)
argument-hint: [optional message]
description: RuboCop pre-flight, then conventional commit
---

## Pre-flight

```
!`bin/rubocop --no-pager -q 2>&1 | tail -5`
```

If violations exist, fix them first. Auto-correct with `bin/rubocop --autocorrect-all`.

## Context

```
!`git status`
!`git diff --staged`
!`git diff`
!`git branch --show-current`
!`git log --oneline -5`
```

## Commit

Generate a conventional commit message from the staged diff. Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `db`, `perf`.

Rules:
- Subject line ≤ 72 chars
- Scope optional: `feat(messages):`, `fix(jobs):`
- Body explains the *why*, not the what
- Never mention AI assistance in the message

If `$ARGUMENTS` is provided, use it as the commit message directly (still run pre-flight).
