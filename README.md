# NTranslate

Menu bar app for macOS:
- read selected text via Accessibility, fallback to clipboard
- translate with `Option+D`
- show popup near cursor
- copy translated text
- speak source text and translated text
- auto-pick source TTS voice for English / Vietnamese / Chinese

## Current flow

1. Select text in another app.
2. Press `Option+D`.
3. NTranslate reads the selection.
4. NTranslate sends the text to the local API.
5. Popup appears near the cursor with the translation.

Current popup actions:
- `Translate`
- `Copy`
- `Speak Src`
- `Speak Tr`

NTranslate does **not** auto-replace the selected text.

## Project files

- Swift source: `Sources/translate/translate.swift`
- Runtime config: `config.json`
- Install script: `install-app.sh`
- App icon source: `icon.jpg`

## Build and run

Run from source tree:

```bash
cd ~/Code/MacOS/translate
swift build -c release
.build/release/translate
```

Note:
- running `.build/release/translate` directly is useful for dev
- macOS may treat Terminal-run builds as a different Accessibility client than `/Applications/NTranslate.app`

## Install app bundle

Build, update installed app, refresh metadata, and reopen:

```bash
cd ~/Code/MacOS/translate
./install-app.sh
```

What `install-app.sh` does:
- builds release binary
- copies binary into `NTranslate.app`
- updates `Info.plist`
- builds `NTranslate.icns` from `icon.jpg` if present
- updates `/Applications/NTranslate.app` in place
- touches the app bundle so LaunchServices/Raycast refresh metadata
- opens the app

## Daily workflow

When you change app code:

```bash
cd ~/Code/MacOS/translate
./install-app.sh
```

You do **not** need to edit `install-app.sh` for normal code changes.

**For Claude Code / agents:** after finishing any code change task in this repo, always run `./install-app.sh` to build, sign, and reinstall the app — don't stop at `swift build`. No need to ask for confirmation first, since it only affects the local `/Applications/NTranslate.app` copy (kills and reopens the app, bumps its patch version).

Only edit `install-app.sh` when packaging details change, for example:
- app name
- bundle id
- binary name
- project path
- extra resources or icons copied into the app bundle

## Config changes

Edit:

```bash
~/Code/MacOS/translate/config.json
```

Then apply without rebuild:
- menu bar app → `Reload Config`

Current TTS-related config keys:

```json
{
  "speechSourceModel": "edge-tts/en-US-AvaMultilingualNeural",
  "speechSourceModelVietnamese": "edge-tts/vi-VN-HoaiMyNeural",
  "speechSourceModelChinese": "edge-tts/zh-CN-XiaoxiaoNeural",
  "speechTargetModel": "edge-tts/vi-VN-HoaiMyNeural"
}
```

## Accessibility permission

NTranslate needs Accessibility permission to read selected text from other apps.

If permission is missing:
- app prompts for Accessibility access on launch or when translation is triggered
- menu bar also has `Grant Accessibility Access`

Grant it in:
- `System Settings` → `Privacy & Security` → `Accessibility`

Important:
- `/Applications/NTranslate.app` is the app you should grant
- Terminal-run binaries can appear as a different client

If macOS still does not recognize the permission after reinstall / rename / bundle-id changes, reset the stale TCC record:

```bash
tccutil reset Accessibility local.ninh.ntranslate
```

Then:
1. quit NTranslate
2. open `/Applications/NTranslate.app`
3. grant Accessibility again

## Raycast icon cache

If Finder shows the icon but Raycast does not, refresh app metadata and restart Raycast:

```bash
touch /Applications/NTranslate.app
```

Then quit and reopen Raycast.

## Current app paths

Installed app:

```bash
/Applications/NTranslate.app
```

Local app bundle:

```bash
~/Code/MacOS/translate/NTranslate.app
```
