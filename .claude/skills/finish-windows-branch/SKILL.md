---
name: finish-windows-branch
description: This skill should be used when a user asks to commit Windows changes, push windows-app directly, push only with no PR, push an existing commit, or keep completed NTranslate Windows work without integration.
---

# Finish Windows Branch

## Core rule

Explicit integration intent is decision. Do not replace it with generic branch menu. `windows-app` stays separate from `main`.

## Intent contract

| User request | Action |
|---|---|
| Commit only | Verify, commit on current policy-compatible Windows branch, do not push |
| Commit and push `windows-app` | Require current branch `windows-app`; verify, commit, push `origin windows-app` |
| Commit and push current task branch | Require branch based on and intended for `windows-app`; verify, commit, push that authorized branch |
| Push existing commit | Verify branch/SHA, push authorized current branch; do not commit dirty work |
| “Push my changes” with dirty work | Commit authorization absent: ask whether to commit; no verify/stage/commit/push until answered |
| Keep branch | Report branch and path; no mutation |
| PR or merge | Require explicit request and policy-compatible target; `main` is blocked |
| Intent missing | Report missing choice, ask once, perform no mutation |

Push never implies commit or PR. Words “push,” “push my changes,” or “push this branch” authorize transfer of existing commits only. When dirty work exists and user did not say “commit,” ask exactly whether dirty changes should be committed; perform no mutation first. Do not create PR unless user explicitly requests one. Never merge `windows-app` into `main`. Do not rebase or cherry-pick between their histories unless user explicitly requests that specific operation.

## Verification gate

Classify changed paths before testing:

| Change class | Required verification |
|---|---|
| Windows source, resources, manifest, build, packaging, release metadata | Script tests, .NET tests, then root installer |
| Tests only | Relevant test suite plus full affected suite |
| Documentation only | Content/diff checks; no installer |
| Read-only analysis | No mutation; no installer |

Required Windows commands, in order:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1
dotnet test .\windows\NTranslate.slnx --no-restore
.\install-app.ps1 -Version <version>
```

Determine `<version>` from task/release intent. For release preparation, require it to exceed latest `windows-v<version>` release. For non-release verification, reuse explicitly authorized task version. If no version was supplied or previously authorized, ask for one and do not install, commit, or push.

For “push existing commit,” require a clean working tree or verify exact committed SHA in a clean worktree; never test unrelated uncommitted files as evidence for pushed commit.

Windows install is unpackaged Inno Setup. Require build and publish to receive `-p:Version=$Version`, because installer filename does not stamp assembly version. Never bypass failed tests or installer verification. Any required failure blocks commit and push; report exact failure.

Installer success report must retain `Version`, `Build`, setup EXE path, checksum path, and test result.

## Commit and push

1. Confirm current branch is `windows-app` or policy-compatible branch based on and intended for `windows-app`; verify expected origin URL and divergence from authorized remote branch. Direct `windows-app` push requires current branch `windows-app`.
2. Review every modified, deleted, and untracked path. Stage only explicitly authorized task changes; ambiguous unrelated work blocks commit.
3. Run `git diff --cached --check` and inspect staged name/status and summary.
4. Commit using repository/harness commit convention.
5. Recheck branch, status, commit contents, and ahead/behind state.
6. Push authorized current branch without force. For direct `windows-app` request:

```bash
git push origin windows-app
```

For task branch, name exact current branch in command; never use implicit push target.

7. Independently compare local `HEAD` with exact pushed remote ref:

```bash
git rev-parse HEAD
git ls-remote origin refs/heads/<authorized-branch>
```

Require matching SHA. Report commit, verification counts, installer fields when applicable, push result, and remaining dirty paths.

## Red flags

- Showing integration menu after user selected direct commit/push.
- Inferring commit authorization from “push” while dirty work exists.
- Creating PR when user requested push only.
- Any mutating command targets `main`.
- Force-push after rejection.
- Staging all dirty files without classifying scope.
- Claiming success before independent remote SHA verification.
- Calling root installer without explicit `-Version`.
- Treating Inno Setup install as MSIX or reading version only from `Package.Current`.

Any red flag means stop and follow explicit intent contract.
