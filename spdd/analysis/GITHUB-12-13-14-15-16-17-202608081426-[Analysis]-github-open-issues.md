# SPDD Analysis: GitHub Open Issues #12–#17

## Original Business Requirement

đọc github issues để lập 1 bảng analysis

Nguồn: GitHub Issues đang mở của `ninhnguyen375/NTranslate`, đọc ngày 2026-08-08.

### Issue #17

- URL: https://github.com/ninhnguyen375/NTranslate/issues/17
- Title: bỏ phần outline, border khi focus vào popup, chỉnh lại border radius của popup đúng chuẩn của apple liquid glass
- Body: *(trống)*

### Issue #16

- URL: https://github.com/ninhnguyen375/NTranslate/issues/16
- Title: bổ sung phím tắt ctrl+option+D, giúp giải lập hành động copy (Edit->Copy hoặc Cmd+C) rồi thực hiện mở popup dịch luôn
- Body: *(trống)*

### Issue #15

- URL: https://github.com/ninhnguyen375/NTranslate/issues/15
- Title: Chế độ learn theo câu dài, bổ sung phiên âm và cách nhớ nhanh của từng cụm/từng chữ
- Body: *(trống)*

### Issue #14

- URL: https://github.com/ninhnguyen375/NTranslate/issues/14
- Title: Cho phép xem All history (hiện tại bị lọc theo Today, Week,...)
- Body: *(trống)*

### Issue #13

- URL: https://github.com/ninhnguyen375/NTranslate/issues/13
- Title: cải tiến xoay quanh chức năng auto-detect
- Body: Yêu cầu LLM trả về ngôn ngữ của bản dịch kèm với kết quả dịch (dạng json) để làm ngôn ngữ nguồn chính xác, thay vì phải tự detect thủ công bằng code; khi có ngôn ngữ nguồn ổn định từ LLM, áp dụng cho TTS button để nhất quán

### Issue #12

- URL: https://github.com/ninhnguyen375/NTranslate/issues/12
- Title: TTS button không theo ngôn ngữ đã chọn trên select
- Body: Chọn ngôn ngữ tiếng Anh nhưng TTS vẫn giữ tiếng Việt

## Domain Concept Identification

### Issue Analysis Table

| Issue | Business outcome | Existing capability | Required change at conceptual level | Priority | Dependency | Main uncertainty |
|---|---|---|---|---|---|---|
| #12 | TTS source uses language explicitly selected by user | Source/target selectors, language-to-speech-model resolution, speech playback state | Make explicit source selection authoritative for source TTS; retain detection only for Auto detect | High | Closely related to #13 | Whether text language or explicit selection wins when they conflict |
| #13 | Auto detect and source TTS use one reliable language identity | Translation request, heuristic detector, history language fields, TTS model resolver | Return detected source language with translation result, validate it, then propagate same identity to UI, history, and source TTS | High | Should precede or be delivered with #12 | JSON contract, allowed language identifiers, fallback when LLM output is invalid |
| #14 | Users can browse complete retained history | Persistent history store, search, Saved filter, four time ranges | Add an unbounded time-range choice without changing storage or search semantics | Medium | None | Whether All becomes default and whether delete-visible may delete entire history |
| #15 | Learn mode supports long sentences with pronunciation and memory aids by phrase/word | Separate word/sentence prompts, configurable prompts, plain-text rendering | Enrich sentence-learning output around meaningful chunks while preserving whole-sentence context | Medium | Benefits from stable source language in #13 | Required depth, output length, pronunciation notation, chunk selection rules |
| #16 | One fixed shortcut copies current selection and opens translation immediately | Configurable global hotkey, optional simulated copy, clipboard restoration, popup flow | Add dedicated `Control+Option+D` intent that always performs simulated copy before translation popup | High | Reuses current selection-copy pipeline | Fixed versus configurable shortcut; behavior on conflict, permission denial, image selection, or copy timeout |
| #17 | Focused popup keeps native Liquid Glass appearance without unwanted outline/border | Borderless key-capable panel, Liquid Glass shell, focus-ring suppression, continuous corner radii | Align focus-state chrome and shell geometry with native visual behavior | Medium | Visual QA on macOS 26 | Which layer produces visible outline; exact Apple-standard radius is not specified |

### Existing Concepts (from codebase)

- **Translation request**: Sends selected text to an OpenAI-compatible chat-completions endpoint and currently returns one plain string — supplies translation and Learn results.
- **Language selection**: Maintains source and target choices, including `Auto detect` — drives translation direction and visible pane labels.
- **Language detection**: Uses local Vietnamese/Chinese heuristics with English fallback — currently resolves auto-detected source and source TTS model.
- **Speech identity and model resolution**: Binds source/result text to a speech model and playback lifecycle — source logic currently detects from text instead of honoring explicit source selection.
- **Translation history**: Persists translation records with source/target language, audio references, and saved status — provides retained data for History UI.
- **History time range**: Filters records by Today, 24h, Week, or Month; filtering already accepts no time range conceptually, but UI exposes no All choice.
- **Learn mode**: Selects word prompt for one token and sentence prompt for multi-token text — sentence prompt already covers meaning, grammar, useful phrases, and one variation.
- **Global hotkey**: Registers one configurable key/modifier combination — invokes popup workflow.
- **Selection acquisition**: Reads Accessibility selection, can synthesize `Command+C`, waits for pasteboard change, and restores prior clipboard contents — directly supports #16.
- **Translation popup**: Borderless, key-capable AppKit window using Liquid Glass shell and continuous corner radii — hosts translation, Learn, language, history, and TTS controls.

### New Concepts Required

- **Resolved source-language identity**: Trusted language identity produced for each translation — shared by source label, history, and source TTS instead of being independently guessed.
- **Structured translation result**: Translation content plus detected source language as one validated business response — only needed for normal text translation with Auto detect unless scope expands.
- **All-history range**: Explicit unbounded history view — composes with History/Saved and search filters.
- **Sentence learning chunk**: Meaningful phrase or word selected from a long sentence for focused pronunciation and memory guidance — remains subordinate to whole-sentence understanding.
- **Copy-and-translate shortcut intent**: Dedicated user action distinct from ordinary popup toggle — guarantees copy simulation before opening/translation.
- **Focus-neutral popup chrome**: Visual state where keyboard focus remains functional without adding non-design outline or border around Liquid Glass shell.

### Key Business Rules

- Explicit source-language selection must govern source TTS; automatic detection applies only when source selection is `Auto detect`.
- Auto-detected language used by UI, history, and TTS must come from the same accepted translation result.
- Invalid, unsupported, or missing LLM language metadata must not prevent users receiving usable translation; deterministic fallback remains necessary.
- Translation text must remain separable from language metadata so metadata never appears in copied output or history result text.
- All history means no time cutoff; search and Saved filtering still apply.
- Delete-visible behavior must remain scoped to currently filtered records; selecting All can therefore broaden destructive scope and requires clear count/confirmation.
- Long-sentence Learn must preserve full-sentence meaning while adding only useful chunks; it must not degrade into exhaustive token-by-token output by default.
- Simulated copy must restore prior clipboard content and must not translate stale clipboard content when copy fails or times out.
- Dedicated shortcut must coexist with configurable global shortcut without duplicate registration or ambiguous dispatch.
- Removing focus visuals must not remove keyboard focus capability, input editing, or accessibility semantics.

## Strategic Approach

### Solution Direction

- Treat issues as three workstreams: language/TTS correctness (#12–#13), workflow and information access (#14–#16), and native popup polish (#17).
- Resolve language identity once at translation boundary, then propagate it through existing popup, speech, and history concepts. Keep current local detector as resilience fallback, not competing source of truth.
- Extend existing UI/state concepts rather than adding new subsystems: unbounded history range in current filter control, richer sentence prompt in existing Learn path, dedicated hotkey intent through existing copy-selection pipeline, and chrome changes within current Liquid Glass hierarchy.
- General data flow for #12–#13: selected source state and input text enter translation request; validated translation result returns content plus source identity; popup presents content; history and source TTS consume same identity.
- General data flow for #16: fixed shortcut event invokes simulated selection copy; successful input resolution populates and opens popup; existing translation action proceeds; prior clipboard is restored.

### Key Design Decisions

- **Language authority**: Explicit selector versus detected metadata has competing meanings. Recommend explicit selector always wins; LLM metadata is authoritative only for Auto detect. This matches user intent and fixes #12 without relying on model behavior.
- **Structured response scope**: Applying JSON to every LLM mode raises migration and parsing risk. Recommend constrain structured result to normal text translation where language identity is needed; keep Learn, image search, and speech contracts unchanged unless later requirements demand metadata.
- **Fallback policy**: Strictly rejecting malformed metadata improves contract purity but can make translation unavailable. Recommend accept valid translation content while falling back to current detector for language identity, with a non-blocking diagnostic path.
- **History All behavior**: Defaulting to All improves discoverability but can load and expose a large destructive scope. Recommend add All as explicit choice while preserving current Today default until product intent says otherwise.
- **Long-sentence learning granularity**: Every token gives complete coverage but produces noisy, costly output. Recommend meaningful phrases plus only notable individual words, chosen in context, with pronunciation and memory cues.
- **Shortcut model**: Replacing configurable shortcut breaks existing user configuration. Recommend retain configurable popup shortcut and add `Control+Option+D` as dedicated copy-and-translate action, subject to conflict checks.
- **Popup visual standard**: Hardcoding a radius claimed as “Apple standard” without a supplied reference is fragile. Recommend preserve native Liquid Glass shell behavior and use one shared shell radius validated visually on supported macOS 26.

### Alternatives Considered

- **Keep local language detection as primary**: Rejected because issue #13 explicitly asks for LLM language metadata and current three-language heuristic cannot reliably cover configured languages.
- **Let text heuristics override explicit language selection for TTS**: Rejected because it reproduces #12 and ignores direct user choice.
- **Add separate history screen for All**: Rejected because current filter already models an absent cutoff; a new screen duplicates search, Saved, delete, and playback behavior.
- **Create a new Learn result domain and renderer immediately**: Rejected because current plain-text configurable prompt can validate desired learning content first; structured rendering is only justified if prompt stability or UX proves insufficient.
- **Reuse configurable hotkey by changing its default modifiers**: Rejected because #16 describes a distinct copy-and-open behavior, while existing shortcut settings and normal popup behavior must remain available.
- **Disable key-window behavior to remove focus outline**: Rejected because popup input requires keyboard focus and editing.

## Risk & Gap Analysis

### Requirement Ambiguities

- **Issues #12, #14, #15, #16, and #17 have empty bodies**: Titles do not define acceptance detail, error behavior, defaults, or exclusions.
- **#12 authority conflict**: Requirement does not state expected behavior when selected language disagrees with actual text language.
- **#13 “ngôn ngữ của bản dịch” wording**: Body later says “ngôn ngữ nguồn”; response must clarify whether metadata represents source, target, or both.
- **#13 schema**: No field names, language naming convention, compatibility policy, or behavior for markdown/code-fenced JSON is defined.
- **#14 default range**: “Cho phép xem All” does not say whether All should be default or merely selectable.
- **#15 “từng cụm/từng chữ”**: Could mean every phrase and word or only useful learning chunks; these produce very different cost and readability.
- **#15 pronunciation**: No notation specified: IPA, transliteration, syllable stress, or TTS.
- **#16 shortcut ownership**: No answer on whether `Control+Option+D` is fixed, configurable, or replacement for current configurable hotkey.
- **#16 “mở popup dịch luôn”**: Unclear whether popup opens with copied content only or also starts translation automatically.
- **#17 visual target**: No screenshot, Apple API reference, radius value, focus state, or exact offending border layer supplied.

### Edge Cases

- **Unsupported LLM language**: Configured speech resolver may lack a matching model, producing inconsistent source TTS unless fallback mapping is explicit.
- **Malformed structured result**: Model may return missing metadata, unsupported language, empty translation, code fences, or extra commentary.
- **Manual source equals target**: Existing grammar-check mode must not be accidentally treated as auto-detected translation.
- **Stale async response**: Language metadata from an older request must not update current popup, TTS, or history after input/language changes.
- **History size**: All may expose many records; responsiveness and delete-visible confirmation become more important.
- **Saved plus All**: Combination must show all saved records independent of age, while search remains additive.
- **Very long Learn input**: Per-chunk pronunciation and memory hints can exceed model/context limits or produce unreadable output.
- **Mixed-language sentence**: One source-language identity and phrase-level pronunciations may be insufficient.
- **Copy shortcut without Accessibility/Input Monitoring permission**: Synthetic copy may fail; popup must not silently use old clipboard content.
- **Copy timeout or unchanged clipboard**: Selected text identical to current clipboard may not change pasteboard count, causing false failure.
- **Image selection under #16**: Existing copy pipeline supports images, but issue wording may intend text only.
- **Hotkey collision**: Existing configured shortcut or another app may already own `Control+Option+D`.
- **Focused child controls**: Removing shell border may leave native focus rings on individual controls; removing all focus indicators harms keyboard accessibility.
- **Display scale and resizing**: Radius and clipping must remain visually consistent across popup sizes and Retina scaling.

### Technical Risks

- **LLM contract reliability**: Prompt-only JSON can drift. Mitigation direction: validated decoding, constrained accepted languages, compatibility fallback, and tests for malformed responses.
- **Cross-cutting language state**: Source identity touches translation completion, labels, history, prefetch, and TTS. Mitigation direction: establish one request-scoped identity and reject stale async updates.
- **Backward compatibility**: Existing endpoint returns OpenAI-compatible envelope whose `message.content` is a string. Changing inner content expectations can break custom prompts/providers. Mitigation direction: explicit transition and fallback policy.
- **TTS cache identity**: Changing speech model selection changes cache/record attachment identity. Mitigation direction: preserve model as part of existing `SpeechIdentity` and invalidate stale requests.
- **History destructive scope**: All plus delete-visible can delete every record. Mitigation direction: preserve snapshot count and explicit irreversible confirmation.
- **Synthetic input timing**: Current pasteboard polling window is short and depends on change count. Mitigation direction: define success semantics before exposing fixed shortcut broadly and retain clipboard restoration invariant.
- **Global hotkey registration**: Two shortcuts need unique IDs and lifecycle handling during config reload. Mitigation direction: centralize registration ownership and conflict reporting.
- **Native visual variance**: Liquid Glass rendering may differ by macOS build, focus state, appearance, and backing scale. Mitigation direction: test supported macOS 26 states in running app; avoid replacing native glass with custom imitation.
- **Test gaps**: Current tests cover detector helpers, prompt selection, history filtering, persistence, and speech state, but not key-window focus chrome, actual global shortcut dispatch, selected-language source TTS, or LLM metadata propagation.

### Acceptance Criteria Coverage

Issues provide no explicit acceptance-criteria lists. Each issue title/body is therefore treated as one provisional AC; gaps below must be resolved before REASONS Canvas finalizes tactical design.

| AC# | Description | Addressable? | Gaps/Notes |
|---|---|---|---|
| #12 | Khi chọn tiếng Anh ở source select, source TTS dùng tiếng Anh thay vì giữ tiếng Việt. | Yes | Must confirm explicit selection precedence and expected behavior for mismatched text. |
| #13 | Translation response includes detected source language in JSON; accepted language drives source identity and TTS consistently. | Partial | Schema, valid language set, fallback, compatibility, and source-versus-target wording unresolved. |
| #14 | History offers All so records are not restricted to Today/24h/Week/Month. | Yes | Default selection and delete-visible scope need confirmation. |
| #15 | Long-sentence Learn includes pronunciation and fast memory guidance for phrases/words. | Partial | Chunk granularity, pronunciation format, output cap, and mixed-language behavior unresolved. |
| #16 | `Control+Option+D` simulates Copy and opens translation popup immediately. | Partial | Fixed/configurable status, auto-run translation, permission failures, image support, and hotkey conflicts unresolved. |
| #17 | Focused popup has no unwanted outline/border and uses Apple Liquid Glass-appropriate corner radius. | Partial | Visual reference and measurable expected radius/state absent; requires running-app visual QA. |

### Recommended Delivery Order

| Order | Issues | Reason |
|---|---|---|
| 1 | #13, #12 | One source-language authority fixes both auto-detect consistency and explicit TTS selection without duplicate logic. |
| 2 | #16 | Existing simulated-copy foundation exists; high-value workflow improvement, but permission/timing semantics need definition. |
| 3 | #14 | Small, isolated extension of existing history filter model. |
| 4 | #15 | Prompt/product design ambiguity and output-cost risk require acceptance examples first. |
| 5 | #17 | Visually scoped but cannot be accepted reliably without reference and running-app QA. |
