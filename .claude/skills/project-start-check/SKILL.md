---
name: project-start-check
description: Use when starting work in NTranslate, checking whether a branch is current, preparing a task branch or worktree, or preserving local changes before coding.
---

# Project Start Check

## Core rule

Inspect before syncing. Project branch policy constrains base. Never stash, reset, pull, checkout, delete, or overwrite dirty checkout automatically.

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
git for-each-ref --format='%(upstream:remotename) %(upstream:remoteref)' "refs/heads/$(git branch --show-current)"
```

Accept only `git@github.com:ninhnguyen375/NTranslate.git`, `https://github.com/ninhnguyen375/NTranslate`, or same HTTPS URL with `.git`. Anything else blocks work.

For read-only status, review, or planning requests: report inspection and stop. Do not fetch or create workspace unless requested information requires refreshed remote state.

## Resolve base

Determine `<base-branch>` before fetch, divergence checks, or worktree creation. Every candidate must satisfy project `CLAUDE.md` branch policy.

1. User-named base, if policy-compatible.
2. Branch explicitly required for task type by project policy.
3. Current branch upstream, if policy-compatible.
4. If none resolves uniquely, stop and ask.

User request conflicting with project branch-separation policy is blocker. Never merge `windows-app` into `main`. A specifically requested rebase, cherry-pick, or other cross-history operation may proceed only when project policy permits that exact operation; it does not change default task base. Never infer `main` from Git default branch. For normal Windows work, policy makes `windows-app` valid base.

Upstream fallback requires upstream remote `origin`; another remote is blocker. Convert `refs/remotes/origin/<base-branch>` upstream ref to `<base-branch>` only after checking this prefix.

Use remote-tracking `<base-ref>` only: `refs/remotes/origin/<base-branch>`. Fetch does not update local base branch. Validate base as one branch name before using it as refspec:

```bash
git check-ref-format --branch "<base-branch>"
git fetch origin "<base-branch>"
git show-ref --verify "refs/remotes/origin/<base-branch>"
git rev-list --left-right --count HEAD..."refs/remotes/origin/<base-branch>"
git log -1 --oneline HEAD
git log -1 --oneline "refs/remotes/origin/<base-branch>"
```

Interpret counts as `<ahead> <behind>`. Report missing local base branch; never create it silently.

## Classify dirty work

Before choosing workspace, compare dirty paths and user request:

- Clearly same task: continue current checkout only when branch/base match; otherwise ask how to carry work.
- Clearly unrelated: preserve untouched and use isolated worktree.
- Ambiguous: stop and ask whether changes belong to task.

Never silently leave relevant in-progress work behind in blank worktree.

## Choose workspace

| State | Action |
|---|---|
| Read-only request | Stay in current checkout; no worktree |
| Dirty, same task, compatible branch | Continue after explicit classification |
| Dirty, unrelated task | Create isolated worktree from `<base-ref>` |
| Existing worktree matches task | Check status, branch, base, and pending commits |
| Existing worktree contains unrelated work | Create another worktree |
| Detached HEAD, unresolved base, or unexpected remote | Stop and report blocker |

Determine primary checkout from first record from `git worktree list --porcelain`. Verify it is not under `.claude/worktrees/` or another `worktrees/` container. Put task path under `<primary-checkout>/.claude/worktrees/`. Never derive container from linked worktree or identify primary checkout by branch name.

Validate task branch, then check collisions:

```bash
git check-ref-format --branch "<task-name>"
git worktree list --porcelain
git show-ref --verify --quiet "refs/heads/<task-name>"
test -e "<absolute-task-path>"
```

Collision means inspect, never delete, overwrite, or silently reuse.

Create and verify:

```bash
git worktree add -b "<task-name>" "<absolute-task-path>" "refs/remotes/origin/<base-branch>"
git -C "<absolute-task-path>" status --short
git -C "<absolute-task-path>" branch --show-current
git -C "<absolute-task-path>" rev-parse HEAD
git rev-parse "refs/remotes/origin/<base-branch>"
```

New worktree requires empty status and matching `HEAD`/`<base-ref>`. Existing task worktree:

```bash
git -C "<existing-task-path>" rev-list --left-right --count HEAD..."refs/remotes/origin/<base-branch>"
git -C "<existing-task-path>" merge-base HEAD "refs/remotes/origin/<base-branch>"
git -C "<existing-task-path>" status --short
```

Ahead-only task commits may continue when task matches. Behind-only or diverged state requires reporting commits and stopping for merge/rebase decision.

## Preserve dirty work

- Never use bare `git stash` or `git stash pop`; stash stack is shared across worktrees.
- Never discard changes without explicit confirmation.
- Never pull into dirty checkout.
- Never move dirty files unless user confirms they belong to task.
- Treat modified binary/plist and untracked `.claude`, `.superpowers`, and plan files as user work.

If user explicitly requires stash, name absolute source/target, require target clean, use unique tag, apply captured SHA, verify target diff, then drop only exact entry. Never use `pop`.

## Red flags

- Command contains `origin/main` before base resolution.
- Local base branch used after fetch instead of `refs/remotes/origin/...`.
- Default branch freshness overrides project branch policy.
- Read-only request creates branch or worktree.
- Dirty paths may match task but are silently abandoned.
- Dirty checkout receives pull, checkout, reset, or implicit file movement.

Any red flag means stop and resolve intent, base, or workspace first.

## Report gate

Report original path/branch, dirty-file classification, resolved base and why, ahead/behind counts, remote URL, chosen workspace path/branch, base commit, and blockers. Do not edit code until all are known.
