---
name: deploy-release
description: This skill should be used when a user asks to publish NTranslate macOS, create a v-prefixed DMG release, or ship a signed DMG from main. It must not be used for Windows releases or ordinary branch merges.
---

# Deploy NTranslate Release

## Core rule

Publish one reviewed, tested, immutable commit. Never bypass failing tests, mutate dirty main, overwrite user changes, or create a release before version metadata reaches `origin/main`.

This skill is macOS-only. For `windows-app`, `windows-v<version>`, setup EXE, or Windows release requests, use `deploy-windows-release`; never apply this workflow to Windows.

**REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion.

## 1. Inspect and protect

```bash
git status --short
git branch --show-current
git worktree list --porcelain
git remote get-url origin
git fetch origin main --tags
gh auth status
gh release list --limit 10
```

Accept only `git@github.com:ninhnguyen375/NTranslate.git`, `https://github.com/ninhnguyen375/NTranslate`, or `https://github.com/ninhnguyen375/NTranslate.git`. Require feature branch ancestry from `origin/main`; reject `windows-app`, branches derived from it, and Windows release changes. When invoked from Windows checkout, create a separate main-compatible worktree. Preserve dirty main untouched. Merge through feature branch + GitHub PR. Never use bare stash/pop. Stage explicit files, never `git add .`. Scan staged files for secrets.

## 2. Test and review feature

Run full tests. Command Line Tools may require framework search path:

```bash
swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

If runtime is missing, validate files belong to active toolchain, then copy only into `.build/<triple>/debug/`:

```bash
xcode-select -p
swift --version
file /Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework/Versions/A/Testing
cp -R /Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework .build/<triple>/debug/
cp /Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib .build/<triple>/debug/
```

Rerun full suite. Never commit `.build` runtime files; remove them after verification.

Run release review for correctness, security, regression, versioning, and data-loss blockers. Fix confirmed blockers, add/update tests, rerun suite. Require all tests pass and no unresolved red findings.

```bash
git diff --check
swift build -c release
```

## 3. Merge feature

Commit explicit feature files using repository/harness commit convention. Push feature branch, create PR, wait for configured required checks, merge, and capture merge SHA:

```bash
git push -u origin <feature-branch>
gh pr create --base main --head <feature-branch> ...
gh pr checks <number> --required --watch
gh pr merge <number> --merge --delete-branch=false
gh pr view <number> --json state,mergeCommit,url
git fetch origin main
```

If no CI checks exist, record that fact; fresh local tests remain mandatory. Verify merge SHA belongs to `origin/main`.

## 4. Calculate release identity

Read latest release and persisted main plist:

```bash
gh api repos/ninhnguyen375/NTranslate/releases/latest --jq '{tag_name,body}'
git show origin/main:NTranslate.app/Contents/Info.plist
```

Parse numeric SemVer. Require persisted main version equals latest published tag; otherwise stop and reconcile history. Require persisted build integer to match latest release notes/build evidence. Calculate target from latest tag using requested bump, default patch. Require `target > latest` and next build greater than published build. Stop on malformed/divergent values; never guess.

Confirm target absent locally, remotely, and on GitHub:

```bash
git show-ref --verify refs/tags/v<TARGET>
git ls-remote --exit-code --tags origin refs/tags/v<TARGET>
gh release view v<TARGET> --repo ninhnguyen375/NTranslate
```

Expected: all not found.

## 5. Generate artifact and metadata locally

Create named clean release worktree from exact `origin/main`; check path/branch collisions first:

```bash
git fetch origin main
git worktree add -b release-v<TARGET> <absolute-release-path> origin/main
git -C <absolute-release-path> status --porcelain
```

Require empty status. Generate notes from `v<PREVIOUS>..HEAD`: user-visible changes, security/reliability, UI fixes, requirements, test count, install steps.

Generate target metadata and a provisional artifact without publishing. Pass the requested bump explicitly:

```bash
VERSION_BUMP=<patch|minor|major> SKIP_UPLOAD=1 NOTES_FILE=<absolute-notes-file> ./release-dmg.sh
```

Treat this DMG as provisional; never upload it. Require output target version/build. Verify script changed only:
- `NTranslate.app/Contents/Info.plist`
- `NTranslate.app/Contents/MacOS/NTranslate`
- `README.md`

Allow `dist/` only when gitignored. Stop on any other tracked/untracked change or secret.

Verify local artifact:

```bash
hdiutil verify dist/NTranslate-<version>-<arch>.dmg
shasum -a 256 dist/NTranslate-<version>-<arch>.dmg
codesign --verify --deep --strict --verbose=2 /Applications/NTranslate.app
```

## 6. Merge release metadata before publication

Commit explicit generated metadata. Push release branch, create metadata PR, wait for checks, merge. Fetch main and capture immutable release SHA:

```bash
git push -u origin release-v<TARGET>
gh pr create --base main --head release-v<TARGET> ...
gh pr checks <number> --required --watch
gh pr merge <number> --merge --delete-branch=false
git fetch origin main --tags
RELEASE_SHA=$(git rev-parse origin/main)
```

Verify `origin/main` plist equals target version/build and README names target DMG.

Create a second clean verification worktree at exact `RELEASE_SHA`. Run full tests, `git diff --check`, and `swift build -c release` again there. Require current exact suite count pass with zero failures.

Set absolute paths once:

```bash
VERIFY_ROOT=<absolute-verification-worktree-at-RELEASE_SHA>
FINAL_DMG="$VERIFY_ROOT/dist/NTranslate-<version>-<arch>.dmg"
FRESH_APP="$VERIFY_ROOT/dist/final-stage/NTranslate.app"
```

Build from exact SHA. Construct `FRESH_APP` in an empty staging directory; never reuse `/Applications/NTranslate.app` or an existing bundle:

```bash
rm -rf "$VERIFY_ROOT/dist/final-stage"
mkdir -p "$FRESH_APP/Contents/MacOS" "$FRESH_APP/Contents/Resources"
cp "$VERIFY_ROOT/.build/release/translate" "$FRESH_APP/Contents/MacOS/NTranslate"
cp "$VERIFY_ROOT/NTranslate.app/Contents/Info.plist" "$FRESH_APP/Contents/Info.plist"
cp -R "$VERIFY_ROOT/NTranslate.app/Contents/Resources/." "$FRESH_APP/Contents/Resources/"
chmod +x "$FRESH_APP/Contents/MacOS/NTranslate"
```

Fail if expected source directories/files are absent. Build expected manifest from `git ls-tree -r "$RELEASE_SHA" -- NTranslate.app/Contents`. Compare both directions against staged bundle: every tracked payload path must exist and no untracked payload path may appear. Explicit exceptions: replace tracked executable with newly built executable; allow generated `_CodeSignature` only after signing. Record sorted relative paths, file modes, symlink targets, sizes, and SHA-256 hashes.

Sign this fresh bundle and use it as sole DMG source. Package final DMG directly with `hdiutil create`; do not call `release-dmg.sh` again because it reads `/Applications` and mutates README:

```bash
codesign --force --deep --options runtime --sign <configured-identity> "$FRESH_APP"
ln -s /Applications "$VERIFY_ROOT/dist/final-stage/Applications"
rm -f "$FINAL_DMG"
hdiutil create -volname "NTranslate <version>" -srcfolder "$VERIFY_ROOT/dist/final-stage" -ov -format UDZO "$FINAL_DMG"
```

Record immutable candidate tuple: `FINAL_DMG` absolute path, inode, size, and SHA-256. Delete provisional DMG by its separate absolute release-worktree path. Never upload a relative path.

Mount final DMG into an empty explicit mountpoint. Require exactly one `NTranslate.app` and one `Applications` symlink whose target is exactly `/Applications`. Compare mounted app to signed `FRESH_APP` both directions using sorted relative path, mode, symlink target, size, and SHA-256 manifests. Run `codesign --verify --deep --strict --verbose=2` on mounted app, then detach. `hdiutil verify` alone is insufficient. This exact SHA and fresh bundle are release candidate.

## 7. Race check and publish exact SHA

Immediately before publication, refetch main/tags and latest release. Require `origin/main == RELEASE_SHA`, latest still equals previous version, target remains greater, and target tag/release remains absent. Re-run this gate immediately before creation; GitHub cannot make latest-check plus create atomic, so abort on any changed observation.

Create draft release first with explicit immutable target, upload exactly one DMG, verify draft fields/asset, then publish:

```bash
gh release create v<TARGET> "$FINAL_DMG" \
  --repo ninhnguyen375/NTranslate \
  --target "$RELEASE_SHA" --draft \
  --title "NTranslate <version>" \
  --notes-file <absolute-notes-file>
```

Before publishing draft, fetch tags and assert every condition again:

```bash
git fetch origin main --tags
test "$(git rev-parse origin/main)" = "$RELEASE_SHA"
test "$(git rev-parse "v<TARGET>^{commit}")" = "$RELEASE_SHA"
gh release view v<TARGET> --json isDraft,isPrerelease,assets,targetCommitish
gh api repos/ninhnguyen375/NTranslate/releases/latest --jq .tag_name
stat -f '%i %z' "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG"
```

Require release remains draft/non-prerelease, tag SHA exact, previous public latest unchanged, and exactly one asset. Compare current absolute path/inode/size/SHA-256 to immutable candidate tuple recorded before upload; never replace or rebaseline tuple. Compare draft asset ID/name/size/digest to same tuple. Any mismatch keeps draft unpublished. Only then publish:

```bash
gh release edit v<TARGET> --repo ninhnguyen375/NTranslate --draft=false
```

If another release appears before draft creation, stop. If any condition changes after draft creation, keep draft unpublished and report conflict.

## 8. Verify publication fail-closed

```bash
git fetch origin --tags
git rev-parse v<TARGET>^{commit}
gh api repos/ninhnguyen375/NTranslate/releases/latest
gh release download v<TARGET> --pattern '*.dmg' --dir <fresh-temp-dir>
```

Query release JSON and require exactly one `.dmg` asset. Extract its exact name, size, ID, and `sha256:<hex>` digest; download that exact filename into an empty directory:

```bash
gh release view v<TARGET> --json assets,tagName,isDraft,isPrerelease,url
mkdir <fresh-temp-dir>
gh release download v<TARGET> --pattern 'NTranslate-<version>-<arch>.dmg' --dir <fresh-temp-dir>
```

Assert:
- tag commit equals `RELEASE_SHA`
- latest release tag/version equals plist version
- release is public, non-draft, non-prerelease
- exactly one DMG asset exists
- asset exact filename/size/digest match local artifact
- downloaded exact file SHA-256 equals local DMG and GitHub `sha256:<hex>` digest
- downloaded DMG passes `hdiutil verify`
- `origin/main` version/build equal release
- installed app version/build and strict signature match

If publication succeeds but verification fails, report partial release immediately. Do not claim completion or silently delete public artifacts.

## Final report

Report feature/metadata PR URLs, main/release SHA, release URL, version/build, DMG filename, SHA-256, test count, build/sign/DMG results, and warnings/skipped steps. Preserve harness-owned worktrees.
