---
name: deploy-windows-release
description: This skill should be used when a user asks to publish NTranslate Windows, create a windows-v release, upload locally built setup EXE assets, or replace assets on an existing Windows release.
---

# Deploy NTranslate Windows Release

## Core rule

Build Windows artifacts locally from reviewed `windows-app`, then publish exactly matching setup EXE and SHA-256 sidecar under `windows-v<version>`. Never target `main` or macOS `v<version>` releases.

**REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion.

## 1. Inspect

```powershell
git status --short
git branch --show-current
git remote get-url origin
git fetch origin windows-app --tags
gh auth status
gh release list --repo ninhnguyen375/NTranslate --limit 20
```

Require:

- Current branch is `windows-app`.
- Origin is `ninhnguyen375/NTranslate`.
- Working tree contains only authorized release changes.
- User explicitly authorized GitHub Release creation or asset upload.
- Target follows strict semantic version format.
- Target tag is `windows-v<version>`.

Do not merge, rebase, or cherry-pick with `main`.

## 2. Determine version

Read latest stable `windows-v<version>` release.

- New release: target version must exceed latest stable Windows version.
- Existing release replacement: target must equal exact user-authorized existing tag. Historical replacement is allowed only when user names that tag explicitly, and artifacts must be rebuilt from that tag's exact commit.

Expected assets:

```text
NTranslate-<version>-win-x64-setup.exe
NTranslate-<version>-win-x64-setup.exe.sha256
```

Do not infer Windows version from macOS `v<version>` releases.

## 3. Build and install locally

Run in order:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1
dotnet test .\windows\NTranslate.slnx --no-restore
.\install-app.ps1 -Version <version>
```

Require:

- Script tests pass.
- Full .NET suite passes.
- Release build has zero errors.
- Installer succeeds and app remains running.
- Installed assembly version equals `<version>.0`.
- Output contains exact setup EXE and checksum paths.

`windows/install-app.ps1` must stamp both build and publish using `-p:Version=$Version`.

## 4. Verify artifacts

```powershell
$exe = ".\windows\artifacts\packages\NTranslate-<version>-win-x64-setup.exe"
$sha = "$exe.sha256"
Test-Path -LiteralPath $exe
Test-Path -LiteralPath $sha
Get-FileHash -LiteralPath $exe -Algorithm SHA256
Get-Content -LiteralPath $sha
```

Require one checksum record:

```text
<64 lowercase hex characters> *NTranslate-<version>-win-x64-setup.exe
```

Recomputed SHA-256 must match sidecar.

## 5. Commit and push

Commit only authorized release changes. Push directly only when user explicitly requests it:

```powershell
git push origin windows-app
```

Capture immutable release SHA and require local/remote equality before publication:

```powershell
$releaseSha = git rev-parse HEAD
$remoteSha = (git ls-remote origin refs/heads/windows-app).Split()[0]
if ($releaseSha -ne $remoteSha) { throw 'Local and remote windows-app SHAs differ.' }
```

For existing-release replacement, check `git rev-parse windows-v<version>^{commit}` equals `$releaseSha`; otherwise rebuild in a clean worktree at exact tag commit before upload.

## 6. Create or update release

Check target first:

```powershell
gh release view windows-v<version> --repo ninhnguyen375/NTranslate
```

If absent, create it only with explicit creation authorization:

```powershell
gh release create windows-v<version> `
  --repo ninhnguyen375/NTranslate `
  --target $releaseSha `
  --title "NTranslate Windows <version>" `
  --notes-file <notes-file>
```

Upload exact local artifacts:

```powershell
gh release upload windows-v<version> `
  ".\windows\artifacts\packages\NTranslate-<version>-win-x64-setup.exe" `
  ".\windows\artifacts\packages\NTranslate-<version>-win-x64-setup.exe.sha256" `
  --clobber `
  --repo ninhnguyen375/NTranslate
```

`--clobber` is allowed only when user authorized replacing assets on that exact release.

## 7. Verify publication

```powershell
gh release view windows-v<version> `
  --repo ninhnguyen375/NTranslate `
  --json tagName,isDraft,isPrerelease,targetCommitish,assets,url
```

Require:

- Exact tag `windows-v<version>`.
- Tag commit equals immutable artifact build commit.
- Public stable release.
- Exactly one expected setup EXE.
- Exactly one expected `.sha256`.
- Asset names and sizes match local files.
- Release target belongs to `windows-app`.
- Downloaded setup EXE SHA-256 matches local artifact and sidecar.

## Final report

Report:

- Commit and remote SHA
- Release URL
- Version and build
- Setup EXE path/name
- SHA-256
- Script and .NET test counts
- Build/install result
- Any skipped physical GUI verification

## Red flags

- Running macOS `release-dmg.sh`.
- Targeting `main` or `v<version>`.
- Publishing artifacts built by GitHub Actions.
- Assembly version differs from installer version.
- Uploading EXE without checksum sidecar.
- Creating or replacing release without explicit authorization.
- Claiming physical popup/tray behavior without observed interaction.
