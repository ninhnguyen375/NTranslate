# Windows Worktree Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate every useful committed and uncommitted Windows change into `windows-app` without losing source or modifying/removing existing worktrees.

**Architecture:** Preserve current WIP in a recovery commit, merge the single descendant smoke branch that subsumes overlapping worktree histories, then apply the tracked five-file sequential WIP as a separate commit. Resolve clipboard overlap by behavior and tests, retaining newest atomic ownership APIs while preserving retry coverage.

**Tech Stack:** Git worktrees, Git merge/diff, .NET, xUnit, Windows App SDK solution files.

## Global Constraints

- Target branch is `windows-app` in `C:\Users\ninhn\Code\NTranslate`.
- Never stash, reset, discard, delete, prune, overwrite, or remove a worktree.
- Preserve all tracked and untracked source before integration.
- Exclude `bin/`, `obj/`, `.vs/`, empty `clip.txt`, and nested worktree metadata.
- Keep `fba0ef2` atomic clipboard sequence ownership behavior.
- Keep bounded `0x800401D0` clipboard retry behavior and tests.
- Run applicable focused and full Windows tests before completion.
- Do not run macOS `./install-app.sh`; Windows-only changes do not affect `NTranslate.app`.

---

### Task 1: Record Recovery Commit

**Files:**
- Create: `docs/superpowers/specs/2026-07-28-windows-worktree-consolidation-design.md`
- Create: `docs/superpowers/plans/2026-07-28-windows-worktree-consolidation.md`
- Create: `windows/tests/NTranslate.Platform.Tests/Clipboard/ClipboardHResultRetryTests.cs`
- Modify: `.gitignore`
- Modify: `windows/src/NTranslate.Platform/Clipboard/OleClipboardService.cs`
- Modify: `windows/tests/NTranslate.Platform.Tests/Clipboard/OleClipboardServiceTests.cs`

**Interfaces:**
- Consumes: Current dirty `windows-app` checkout at `92e39d1`.
- Produces: Named recovery commit containing every current source/doc change.

- [ ] **Step 1: Verify exact recovery inventory**

Run:

```powershell
git status --short
git diff --check
git diff -- .gitignore windows/src/NTranslate.Platform/Clipboard/OleClipboardService.cs windows/tests/NTranslate.Platform.Tests/Clipboard/OleClipboardServiceTests.cs
git diff --no-index -- NUL windows/tests/NTranslate.Platform.Tests/Clipboard/ClipboardHResultRetryTests.cs
```

Expected: only listed source/docs changes; `git diff --check` exits 0.

- [ ] **Step 2: Run focused clipboard tests**

Run:

```powershell
dotnet test windows/tests/NTranslate.Platform.Tests/NTranslate.Platform.Tests.csproj --filter "FullyQualifiedName~Clipboard"
```

Expected: all non-opt-in clipboard tests pass.

- [ ] **Step 3: Commit recovery point**

Run:

```powershell
git add .gitignore docs/superpowers/specs/2026-07-28-windows-worktree-consolidation-design.md docs/superpowers/plans/2026-07-28-windows-worktree-consolidation.md windows/src/NTranslate.Platform/Clipboard/OleClipboardService.cs windows/tests/NTranslate.Platform.Tests/Clipboard/OleClipboardServiceTests.cs windows/tests/NTranslate.Platform.Tests/Clipboard/ClipboardHResultRetryTests.cs
git commit -m "test(windows): preserve clipboard retry work" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Expected: clean checkout and recoverable commit on `windows-app`.

### Task 2: Merge Descendant Smoke History

**Files:**
- Merge changes across `windows/NTranslate.slnx`, `windows/src/**`, and `windows/tests/**` from `fix/windows-smoke-regressions`.
- Resolve if conflicted: `windows/src/NTranslate.Platform/Clipboard/OleClipboardService.cs`
- Resolve if conflicted: `windows/tests/NTranslate.Platform.Tests/Clipboard/OleClipboardServiceTests.cs`
- Resolve if conflicted: `windows/tests/NTranslate.Platform.Tests/Clipboard/ClipboardHResultRetryTests.cs`

**Interfaces:**
- Consumes: Recovery commit from Task 1 and branch tip `fix/windows-smoke-regressions` at `48268c1`.
- Produces: Merge commit containing sixteen ordered descendant commits plus preserved retry behavior.

- [ ] **Step 1: Verify source branch identity and ancestry**

Run:

```powershell
git rev-parse fix/windows-smoke-regressions
git merge-base --is-ancestor 92e39d1 fix/windows-smoke-regressions
git rev-list --reverse 92e39d1..fix/windows-smoke-regressions
git status --short
```

Expected: tip `48268c13f3180469c03d858cbebd3fcf25f0fc34`, ancestry command exits 0, sixteen commits, clean target.

- [ ] **Step 2: Merge without auto-commit**

Run:

```powershell
git merge --no-ff --no-commit fix/windows-smoke-regressions
```

Expected: merge stages all non-overlapping files; clipboard conflicts may remain.

- [ ] **Step 3: Resolve clipboard behavior semantically**

Inspect merged files and ensure these exact properties coexist:

```text
WriteUnicodeTextAndGetSequence(...) returns sequence captured after write.
RestoreIfUnchangedAndGetSequence(...) compares expected sequence atomically and returns resulting sequence.
ClipboardHResultRetry retries only 0x800401D0, stops after three attempts, and rethrows non-transient/exhausted failures.
OleClipboardService callers use atomic sequence APIs rather than superseded split ownership checks.
```

Stage only resolved source/test files:

```powershell
git add windows/src/NTranslate.Platform/Clipboard/OleClipboardService.cs windows/tests/NTranslate.Platform.Tests/Clipboard/OleClipboardServiceTests.cs windows/tests/NTranslate.Platform.Tests/Clipboard/ClipboardHResultRetryTests.cs
git diff --check
git diff --cached --check
```

Expected: no unmerged paths and no whitespace errors.

- [ ] **Step 4: Run focused merge tests**

Run:

```powershell
dotnet test windows/tests/NTranslate.Platform.Tests/NTranslate.Platform.Tests.csproj --filter "FullyQualifiedName~Clipboard"
dotnet test windows/tests/NTranslate.Core.Tests/NTranslate.Core.Tests.csproj
```

Expected: all tests pass.

- [ ] **Step 5: Commit merge**

Run:

```powershell
git commit -m "merge: consolidate Windows smoke fixes" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Expected: two-parent merge commit; second parent is `48268c1`.

### Task 3: Import Sequential UI and Tray WIP

**Files:**
- Modify: `windows/src/NTranslate.App/AppComposition.cs`
- Modify: `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- Modify: `windows/src/NTranslate.Platform/Windows/TrayIcon.cs`
- Modify: `windows/tests/NTranslate.App.Tests/Popup/TranslationViewModelTests.cs`
- Modify: `windows/tests/NTranslate.Platform.Tests/Windows/TrayIconTests.cs`

**Interfaces:**
- Consumes: Tracked diff from `C:\Users\ninhn\Code\NTranslate\.claude\worktrees\sequential-greeting-candy` based on `48268c1`.
- Produces: UI-dispatched translation completion and tray activation callbacks for `NIN_SELECT`, `NIN_KEYSELECT`, and `WM_LBUTTONDBLCLK`, with tests.

- [ ] **Step 1: Export tracked diff without generated output**

Run:

```powershell
git -C "C:\Users\ninhn\Code\NTranslate\.claude\worktrees\sequential-greeting-candy" diff --binary -- windows/src/NTranslate.App/AppComposition.cs windows/src/NTranslate.App/Popup/TranslationViewModel.cs windows/src/NTranslate.Platform/Windows/TrayIcon.cs windows/tests/NTranslate.App.Tests/Popup/TranslationViewModelTests.cs windows/tests/NTranslate.Platform.Tests/Windows/TrayIconTests.cs > "$env:TEMP\ntranslate-sequential-wip.patch"
git apply --check "$env:TEMP\ntranslate-sequential-wip.patch"
```

Expected: patch contains exactly five tracked files and applies cleanly.

- [ ] **Step 2: Apply patch**

Run:

```powershell
git apply "$env:TEMP\ntranslate-sequential-wip.patch"
git status --short
git diff --check
```

Expected: exactly five modified tracked files; no `bin/` or `obj/` additions.

- [ ] **Step 3: Run focused UI and tray tests**

Run:

```powershell
dotnet test windows/tests/NTranslate.App.Tests/NTranslate.App.Tests.csproj --filter "FullyQualifiedName~TranslationViewModel"
dotnet test windows/tests/NTranslate.Platform.Tests/NTranslate.Platform.Tests.csproj --filter "FullyQualifiedName~TrayIcon"
```

Expected: all focused tests pass.

- [ ] **Step 4: Commit sequential WIP**

Run:

```powershell
git add windows/src/NTranslate.App/AppComposition.cs windows/src/NTranslate.App/Popup/TranslationViewModel.cs windows/src/NTranslate.Platform/Windows/TrayIcon.cs windows/tests/NTranslate.App.Tests/Popup/TranslationViewModelTests.cs windows/tests/NTranslate.Platform.Tests/Windows/TrayIconTests.cs
git commit -m "fix(windows): dispatch translation and tray activation" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Expected: clean checkout after commit.

### Task 4: Verify Consolidation Completeness

**Files:**
- Inspect: all worktrees from `git worktree list --porcelain`
- Test: `windows/NTranslate.slnx`

**Interfaces:**
- Consumes: Consolidated `windows-app` history from Tasks 1-3.
- Produces: Evidence that tests pass and no useful code remains exclusive to another worktree.

- [ ] **Step 1: Run full Windows suite**

Run:

```powershell
dotnet test windows/NTranslate.slnx
```

Expected: all discovered test projects build and pass.

- [ ] **Step 2: Build production solution**

Run:

```powershell
dotnet build windows/NTranslate.slnx --no-restore
```

Expected: build succeeds with no errors.

- [ ] **Step 3: Verify graph and diff hygiene**

Run:

```powershell
git diff --check
git status --short
git log --graph --decorate --oneline -25
git merge-base --is-ancestor fix/windows-smoke-regressions windows-app
git rev-list --left-right --count windows-app...fix/windows-smoke-regressions
```

Expected: clean target; smoke branch is ancestor; counts show `windows-app` ahead and not behind.

- [ ] **Step 4: Re-scan every worktree for exclusive source**

For each path from `git worktree list --porcelain`, run:

```powershell
git -C "<absolute-worktree-path>" status --short
git cherry windows-app "<worktree-branch>"
```

For detached nested worktree, compare its HEAD directly:

```powershell
git merge-base --is-ancestor f7fab5c windows-app
```

Expected: remaining uncommitted files outside target are generated output, empty artifact, nested worktree metadata, or the now-integrated five-file sequential diff. No useful commit remains absent.

- [ ] **Step 5: Report without cleanup**

Report:

```text
- Recovery, merge, and sequential commit SHAs.
- Focused/full test and build results.
- Any warnings or skipped opt-in clipboard integration tests.
- Confirmation that no worktree was removed or modified.
- Remaining generated/untracked artifacts by worktree.
```

Do not run `git worktree remove`, `git worktree prune`, `git clean`, or deletion commands.
