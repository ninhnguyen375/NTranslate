---
name: project-start-check
description: This skill should be used when starting work in NTranslate, checking whether main is current, preparing a task branch or worktree, or preserving existing local changes before coding. Trigger for “start this task,” “sync main safely,” “check the repo before coding,” and “create a worktree without losing my changes.”
---

# Project Start Check

## Core rule

Inspect before syncing. Never stash, reset, pull, checkout, delete, or overwrite a dirty checkout automatically.

## Inspect

Run read-only checks first:

```bash
pwd
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git status --short
git remote get-url origin
git worktree list --porcelain
git rev-list --left-right --count HEAD...origin/main
```

Accept only `git@github.com:ninhnguyen375/NTranslate.git`, `https://github.com/ninhnguyen375/NTranslate`, or same HTTPS URL with `.git`. Report anything else as blocker. Then refresh remote state and measure current branch separately from local main:

```bash
git fetch origin main
git rev-list --left-right --count HEAD...origin/main
git show-ref --verify --quiet refs/heads/main && git rev-list --left-right --count refs/heads/main...origin/main
git log -1 --oneline HEAD
git log -1 --oneline origin/main
```

Interpret counts as `<ahead> <behind>`. Report absent local main rather than creating it silently. A clean current main requires empty `git status --short` and local-main counts `0 0` after fetch.

## Choose workspace

| State | Action |
|---|---|
| Dirty checkout | Preserve untouched; create isolated task worktree from `origin/main` |
| Clean main | Create isolated task worktree from `origin/main` |
| Existing worktree matches task | Continue only after checking its status, branch, base, and pending commits |
| Existing worktree contains unrelated work | Create another worktree |
| Detached HEAD or unexpected remote | Stop and report blocker |

Determine primary checkout from first `worktree` record emitted by `git worktree list --porcelain`; Git lists main working tree first. Verify it is not itself under `.claude/worktrees/` or another `worktrees/` container. Set absolute task path under `<primary-checkout>/.claude/worktrees/`. Report blocker if topology is missing or nested; never derive container from current linked worktree or assume branch `main` identifies primary checkout.

Before creating, check collisions:

```bash
git worktree list --porcelain
git show-ref --verify --quiet refs/heads/<task-name>
test -e <absolute-task-path>
```

If branch or path exists, inspect it. Never delete, overwrite, or silently reuse it.

Create new workspace:

```bash
git worktree add -b <task-name> <absolute-task-path> origin/main
```

Use short kebab-case task name. Verify:

```bash
git -C <absolute-task-path> status --short
git -C <absolute-task-path> branch --show-current
git -C <absolute-task-path> rev-parse HEAD
git rev-parse origin/main
```

For newly created worktree, require empty status and matching `HEAD`/`origin/main` before editing. For existing task worktree, measure divergence and base explicitly:

```bash
git -C <existing-task-path> rev-list --left-right --count HEAD...origin/main
git -C <existing-task-path> merge-base HEAD origin/main
git -C <existing-task-path> status --short
```

Ahead-only task commits may continue when task matches. Behind-only or diverged state requires reporting commits and stopping for a rebase/merge decision; never update it silently.

## Preserve dirty work

- Never use bare `git stash` or `git stash pop`; stash stack is shared across worktrees.
- Never discard changes without explicit confirmation.
- Never pull into dirty main.
- Never move dirty files into task branch unless user confirms they belong there.
- Treat modified binary/plist and untracked `.claude`, `.superpowers`, plan files as user work.

If user explicitly requests moving changes, prefer dedicated branch plus temporary WIP commit after confirmation. If stash is explicitly required, name absolute source and target paths, require target clean, and scope every command:

```bash
git -C <absolute-source-path> stash push -u -m "<unique-session-tag>"
git -C <absolute-source-path> stash list --format='%H %gs'
git -C <absolute-target-path> status --short
git -C <absolute-target-path> stash apply <captured-sha>
git -C <absolute-target-path> status --short
git -C <absolute-target-path> diff --stat
# After user-visible verification, locate exact tag again and drop only that entry.
```

Never use `pop`; never drop before verifying target diff.

## Report gate

Report original path/branch, dirty files, ahead/behind counts, remote URL, chosen worktree path/branch, base commit, and blockers. Do not edit code until all are known.
