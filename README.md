# NTranslate

Native macOS menu bar app that translates selected text with a global hotkey. Reads the selection via Accessibility (clipboard fallback), calls an OpenAI-compatible chat/TTS API, and shows a popup near the cursor.

Designed to work with **[9router](https://github.com/decolua/9router)** — a local OpenAI-compatible AI gateway (`http://localhost:20128/v1`) that routes chat and speech to many upstream providers. Default `config.json.example` points at 9router’s chat and TTS endpoints; any other OpenAI-compatible API also works.

NTranslate does **not** auto-replace the selected text.

## Features

- Global hotkey (default `Option+D`) to translate the current selection
- Popup near the cursor with **Translate**, **Learn**, **Copy**, **Speak Src**, **Speak Tr**
- Same source/target language → grammar check instead of translation
- TTS for source and translated text (voice models configurable)
- Configurable languages, prompts, hotkey, and UI size
- Runtime config in Application Support (API key never needs to live in the repo)
- Built for [9router](https://github.com/decolua/9router) (local OpenAI-compatible gateway)

## Requirements

- macOS 26+ (see `Package.swift`)
- Swift 6.3 toolchain (`swift-tools-version: 6.3`)
- [9router](https://github.com/decolua/9router) running locally (recommended), or any OpenAI-compatible chat + speech API
- Accessibility permission (to read selected text from other apps)
- Optional: Apple code-signing identity for installing into `/Applications`

## Quick start

1. Install and start [9router](https://github.com/decolua/9router) (default API: `http://localhost:20128/v1`).
2. Create an API key in the 9router dashboard and note a chat model (+ TTS model if you use Speak).

```bash
git clone https://github.com/<you>/NTranslate.git
cd NTranslate
cp config.json.example config.json
# Edit config.json: set apiKey (from 9router), model, languages, etc.
# Default apiBaseURL / speechURL already target 9router on localhost:20128.
./install-app.sh
```

Then grant Accessibility:

**System Settings → Privacy & Security → Accessibility → enable NTranslate**

Use the installed app at `/Applications/NTranslate.app` (not a Terminal-run binary) so TCC attaches to the right client.

### Dev run (without installing)

```bash
swift build -c release
.build/release/translate
```

macOS may treat a Terminal-launched binary as a different Accessibility client than the installed app bundle.

## Configuration

| Location | Role |
| --- | --- |
| `config.json.example` | Template committed to the repo (placeholder `apiKey`) |
| `config.json` | Local seed file — **gitignored**; copy from the example |
| `~/Library/Application Support/NTranslate/config.json` | Runtime config the app actually reads |

`install-app.sh` seeds Application Support from `config.json` (or the example) when missing. To overwrite:

```bash
FORCE_CONFIG=1 ./install-app.sh
```

After editing the Application Support file, use the menu bar item **Reload Config**.

### Important keys

```json
{
  "apiBaseURL": "http://localhost:20128/v1/chat/completions",
  "speechURL": "http://localhost:20128/v1/audio/speech",
  "apiKey": "your-api-key-here",
  "model": "your-model-id",
  "sourceLang": "Auto detect",
  "targetLang": "Vietnamese",
  "nativeLang": "Vietnamese",
  "languages": ["Auto detect", "English", "Vietnamese", "Chinese"],
  "targetLanguages": ["English", "Vietnamese"],
  "maxTranslateLength": 5000,
  "hotkey": {
    "key": "D",
    "option": true,
    "command": false,
    "control": false,
    "shift": false
  },
  "ui": {
    "width": 720,
    "height": 320,
    "autoCopy": false,
    "simulateCopy": false
  }
}
```

Prompts (`systemPrompt`, `learnPrompt`, `grammarPrompt`) and TTS model IDs are also in the example file. Placeholders like `{{config.sourceLang}}` and `{{lang}}` are substituted at request time.

**Never commit a real `apiKey`.** Keep secrets only in Application Support or a local `config.json`.

## How it works

1. Select text in another app.
2. Press the configured hotkey (default `Option+D`).
3. NTranslate reads the selection via Accessibility, or falls back to the clipboard (optional simulated copy).
4. Text is sent to `apiBaseURL` with `Authorization: Bearer <apiKey>`.
5. A popup appears near the cursor with the result.

## Accessibility troubleshooting

If permission looks stuck after reinstall / rename / bundle id changes:

```bash
tccutil reset Accessibility local.ninh.ntranslate
```

1. Quit NTranslate  
2. Open `/Applications/NTranslate.app`  
3. Grant Accessibility again  

## Project layout

```
Sources/translate/   Swift sources (menu bar app, selection, API, UI)
Tests/translateTests/
config.json.example  Public config template
install-app.sh       Build, sign, install to /Applications
Package.swift
```

## Build / install script

`./install-app.sh` will:

- `swift build -c release`
- Refresh the local `NTranslate.app` bundle
- Optionally rebuild icons from `icon.jpg`
- Bump `CFBundleVersion` / display version
- Install to `/Applications/NTranslate.app`
- Seed Application Support config when missing
- Code-sign and reopen the app

Set your signing identity before install (see Security notes below). Version bump:

```bash
VERSION_BUMP=minor ./install-app.sh
```

## Privacy

- Selected text is sent to the API endpoint you configure (`apiBaseURL` / `speechURL`).
- Accessibility is used only to read the focused selection for translation.
- The app does not ship with cloud credentials; you bring your own API.

## Security notes for contributors

- `config.json` is gitignored — do not force-add it.
- Do not commit real API keys, `.env`, or signing certificates.
- Prefer not to commit built binaries under `NTranslate.app/Contents/MacOS/`.

## License

Choose and add a `LICENSE` file before publishing (e.g. MIT). Until then, all rights reserved by the author.
