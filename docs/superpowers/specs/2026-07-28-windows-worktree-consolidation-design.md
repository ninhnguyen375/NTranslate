# Windows Worktree Consolidation Design

## Goal

Consolidate every useful Windows implementation and test from current Git worktrees into `windows-app` without losing committed or uncommitted source. Preserve all worktrees until integrated result passes verification.

## Scope

Include:

- Current `windows-app` clipboard retry work and `.gitignore` change.
- Sixteen descendant commits ending at `48268c1` on `fix/windows-smoke-regressions`.
- Five tracked source/test changes in `worktree-sequential-greeting-candy` for UI dispatch and tray activation.
- Tests associated with all integrated behavior.

Exclude:

- `bin/`, `obj/`, `.vs/`, and other generated build output.
- Empty `clip.txt`.
- Nested worktree directory as content.
- Old branch commits already patch-equivalent to commits in `windows-app`.
- Old implementations superseded by newer clipboard ownership and capture logic.

## Safety Model

1. Create recoverable commits before integrating descendants. Never stash, reset, discard, or overwrite uncommitted source.
2. Keep all existing worktrees and branches unchanged during consolidation.
3. Integrate descendant history in dependency order rather than replaying overlapping old branches.
4. Resolve clipboard overlap semantically: retain latest atomic ownership implementation, then verify every retry/integration-test intent from current WIP remains represented.
5. Import sequential worktree changes from its tracked diff only. Never copy generated files.
6. Stop on ambiguous conflicts or failed tests; retain recoverable commits and worktrees.

## Integration Flow

### 1. Preserve Current WIP

Commit current `windows-app` changes as a recovery point:

- `.gitignore`
- `OleClipboardService.cs`
- `OleClipboardServiceTests.cs`
- `ClipboardHResultRetryTests.cs`
- This design document

Run focused clipboard tests before and after commit when practical.

### 2. Integrate Descendant Commit Chain

Merge `fix/windows-smoke-regressions` into `windows-app`. The branch is a direct descendant of current `windows-app`, but current WIP commit creates divergence. Use a normal merge so both recovery history and sixteen ordered feature commits remain visible.

Expected overlap is limited to clipboard files. Resolution rules:

- Prefer `fba0ef2` atomic sequence ownership APIs and later callers.
- Preserve retry handling for `0x800401D0`, bounded attempts, and non-transient error behavior.
- Preserve opt-in integration test coverage where not already present.
- Do not restore superseded non-atomic ownership APIs.

### 3. Import Sequential WIP

Capture tracked diff from `worktree-sequential-greeting-candy` and apply it to integrated `windows-app`. Its base is `48268c1`, so source should apply cleanly after smoke chain integration.

Included files:

- `windows/src/NTranslate.App/AppComposition.cs`
- `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- `windows/src/NTranslate.Platform/Windows/TrayIcon.cs`
- `windows/tests/NTranslate.App.Tests/Popup/TranslationViewModelTests.cs`
- `windows/tests/NTranslate.Platform.Tests/Windows/TrayIconTests.cs`

Commit this as a separate functional unit. Do not include worktree build output.

## Verification

Run from consolidated `windows-app`:

1. `git diff --check`
2. Focused clipboard, popup/view-model, and tray tests.
3. Full Windows solution test suite.
4. Build Windows solution if tests do not already build all production projects.
5. Compare commit graph and changed file inventory against every worktree.
6. Confirm no useful tracked or untracked source remains exclusive to another worktree.
7. Confirm every existing worktree still exists and was not modified by consolidation.

Generated integration tests requiring `NTRANSLATE_RUN_CLIPBOARD_INTEGRATION=1` remain opt-in unless environment supports safe clipboard mutation.

## Success Criteria

- `windows-app` contains all sixteen descendant commits and sequential WIP behavior.
- Atomic clipboard ownership behavior survives merge.
- Clipboard retry behavior and tests survive merge.
- UI dispatcher and tray activation behavior have tests.
- Full applicable Windows tests pass.
- `git diff --check` passes.
- No worktree is deleted, reset, stashed, or silently modified.
- Remaining exclusive files outside `windows-app` are generated output, empty artifacts, or Git worktree metadata only.

## Failure Handling

On test or merge failure, keep merge state and recovery commits intact while diagnosing. Abort only when necessary and only through non-destructive Git operations that return to committed recovery points. Never delete source or worktrees to resolve integration problems.
