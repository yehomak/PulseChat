---
allowed-tools: Bash(git *), Bash(bin/rubocop:*), Bash(bundle exec brakeman:*), Bash(bundle exec bundler-audit:*), Bash(bin/rails test:*), Bash(gh *)
description: Full Rails gate (rubocop + brakeman + test), then structured PR
disable-model-invocation: true
---

## Pre-flight gate

Run with Bash tool:
```bash
bin/rubocop --no-pager -q 2>&1 | tail -5
bundle exec brakeman --no-pager -q 2>&1 | tail -10
bin/rails test 2>&1 | tail -20
```

Stop and fix any failures before opening the PR.

## Context

Run with Bash tool:
```bash
git log main..HEAD --oneline
git diff main...HEAD --stat
```

## PR description

Open a PR with this structure:

```
## What
One-line summary of the change.

## Why
Motivation. Link to ticket/issue if applicable.

## Testing
- [ ] `bin/rails test` passes
- [ ] No N+1 (strict_loading check)
- [ ] Callbacks use `*_commit` variant where async
- [ ] RuboCop clean
- [ ] Brakeman clean
- [ ] Happy path tested
- [ ] Edge cases covered: [list them]

## Notes
Migration notes, deployment order, rollback plan if relevant.

## AI-assisted
Yes — tasks 1-2. Reviewed and can explain all code.
```
