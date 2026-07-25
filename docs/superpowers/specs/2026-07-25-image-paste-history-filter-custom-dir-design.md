# Design Spec: Image Paste, History Filter, Custom History Directory

## Overview
Enhance NTranslate with three key improvements:
1. **Image Paste Support in Input Text View**: Allow users to paste images directly into `inputTextView` via Command+V or context menu.
2. **History Window Filtering**: Add freetext search, "All History" vs "Saved Words" filter, and a "Clear Filter" button in `HistoryWindowController`.
3. **Custom History Directory Config**: Add `historyDirectory` property to `AppConfig`, allowing custom storage path while audio folder automatically resides inside it (`<historyDirectory>/audio`).

---

## Component Details

### 1. Image Paste Support (`InputTextView`)
- **Class**: Create `InputTextView: NSTextView` in `Sources/translate/PopoverController.swift` (or dedicated view file).
- **Behavior**:
  - Override `paste(_ sender: Any?)`.
  - Inspect `NSPasteboard.general` for image types (`.png`, `.tiff`, `NSImage`).
  - If image data present: read data, call handler to set `pendingImage` and update UI placeholder `[Image from clipboard]`.
  - If no image data: fallback to `super.paste(sender)`.
  - Also handle drag-and-drop or standard pasteboard types if needed.

### 2. History Window Filter (`HistoryWindowController`)
- **UI Components in Top Bar**:
  - `searchField: NSSearchField` (freetext filter matching `sourceText` and `resultText`, case-insensitive).
  - `filterSegmentedControl: NSSegmentedControl` with segments: `[0: All history, 1: Saved words]`.
  - `clearFilterButton: NSButton` (resets search text and sets segment back to 0).
- **Filtering Logic**:
  - Maintain `filteredRecords: [TranslationRecord]`.
  - Recompute `filteredRecords` whenever `searchField` text changes, segment selection changes, or `clearFilterButton` clicked.
  - `numberOfRows` and `rowView` use `filteredRecords`.

### 3. Custom History Directory (`AppConfig` & `TranslationHistoryStore`)
- **AppConfig**:
  - Add `var historyDirectory: String?` (optional, default `nil`).
  - Decode from JSON if present.
- **TranslationHistoryStore**:
  - Update `init(config: AppConfig, fileManager: FileManager = .default)`.
  - If `config.historyDirectory` is non-empty string, expand tilde (`~`) and use URL.
  - Subfolder `audio/` is created inside `historyDirectory` as `directoryURL.appendingPathComponent("audio")`.
  - Backwards compatibility: Fallback to default `~/Library/Application Support/NTranslate/` if omitted/nil.

---

## Testing Plan
- Unit test in `TranslationHistoryStoreTests.swift`:
  - Test initialisation with custom directory URL.
  - Test history filtering logic (Saved vs All, search query).
- Build test: `./install-app.sh`.
