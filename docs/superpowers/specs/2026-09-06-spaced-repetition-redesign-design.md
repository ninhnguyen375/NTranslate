# Spaced Repetition redesign

Ngày: 2026-09-06
Prototype: `docs/prototypes/spaced-repetition-redesign.html`

## 1. Vấn đề

Cửa sổ Spaced Repetition hiện dồn ba trạng thái (home, phiên học, hoàn thành) vào một stack
dọc duy nhất trong `Sources/translate/ReviewWindowController.swift` (1668 dòng). Hệ quả:

- Home chỉ có một dòng `statsLabel`: "N saved · M mastered · K-day streak". Không biết bao nhiêu
  thẻ due, bao nhiêu thẻ mới, bao nhiêu thẻ đang là leech.
- Trong phiên chỉ có `progressLabel` một dòng. Không có thanh tiến độ, không biết đúng/sai bao nhiêu.
- Nút Again/Hard/Easy không hiện khoảng cách ôn kế tiếp, người học chấm điểm mù.
- Kết thúc phiên chỉ đổi icon checkmark, không có tổng kết, không có đường xử lý thẻ vừa sai.
- Ba màn hình dùng chung `termLabel`, `progressLabel`, `statsLabel`, `sourceContainer`, nên mỗi lần
  chuyển màn phải ẩn/hiện chéo hàng chục view (`presentNonCardChrome()`, `hideSourceGiveaways()`).
- App là accessory (`install-app.sh:63` đặt `LSUIElement`, `Sources/translate/main.swift:7` gọi
  `setActivationPolicy(.accessory)`), nên `NSApp.mainMenu` dựng trong `PopoverController+Menu.swift`
  không bao giờ được vẽ. Không có menu bar, không có Dock icon, không Cmd+Tab lại được cửa sổ học.
- Không có đường học từ mới: kho `Resources/vocab-en-vi.json` có 7410 thẻ dựng sẵn nhưng chỉ được
  tra khi người dùng gõ đúng từ đó vào popup.

## 2. Phạm vi

Trong phạm vi:

1. Tách `ReviewWindowController` thành ba view riêng cộng một controller điều phối.
2. Thiết kế lại home thành dashboard có phân nhóm thẻ, streak, lọc theo trạng thái, mục tiêu phiên, chọn kiểu hỏi.
3. Thiết kế lại màn hình phiên học: top bar cố định, tiến độ, metadata thẻ, interval trên nút chấm điểm.
4. Thêm màn hình tổng kết phiên.
5. Thêm màn hình "Học từ mới" duyệt kho từ vựng dựng sẵn.
6. Bật menu bar và Dock icon khi cửa sổ Study mở.

Ngoài phạm vi: tag người dùng tự đặt cho thẻ, mục tiêu phiên theo phút, tách luồng reading
passage / weave ra khỏi controller, thay đổi thuật toán SM-2 trong `ReviewPlanner`.

## 3. Kiến trúc

### 3.1 Tách view

`ReviewWindowController` giữ: store, translator, config, state phiên, chấm điểm SRS, key monitor,
speech playback, reading passage và weave. Nó nhét đúng một view con vào `cardView` mỗi lúc.

| View | File | Delegate gửi ra controller |
| --- | --- | --- |
| `ReviewHomeView` | `Sources/translate/ReviewHomeView.swift` | `start(filter:limit:kind:)`, `openNewWords()`, `openReading()`, `openPassages()` |
| `ReviewSessionView` | `Sources/translate/ReviewSessionView.swift` | `grade(_:)`, `reveal()`, `submitAnswer(_:)`, `chooseContrast(_:)`, `undo()`, `hideCard()`, `goHome()`, `speak(slow:)`, `openInTranslate()` |
| `ReviewSummaryView` | `Sources/translate/ReviewSummaryView.swift` | `redrillMissed()`, `continueSession()`, `goHome()` |
| `NewWordsView` | `Sources/translate/NewWordsView.swift` | `markKnown()`, `markLearn()`, `markSkip()`, `speak(slow:)`, `changeLevel(_:)`, `goHome()` |

Mỗi view chỉ nhận một struct dữ liệu thuần và một delegate. Không view nào cầm `TranslationHistoryStore`.

Reading passage giữ nguyên trong controller ở đợt này.

### 3.2 Logic thuần mới

Hai file không phụ thuộc AppKit, kiểm được bằng script standalone theo đúng lối `ReviewPlanner`:

`Sources/translate/DeckStats.swift`

```swift
struct DeckStats: Equatable, Sendable {
    enum Bucket: CaseIterable { case new, learning, due, mastered, leech }
    var counts: [Bucket: Int]
    var dayStreak: Int
    var last7Days: [Int]      // số thẻ đã ôn mỗi ngày, phần tử cuối là hôm nay
    var totalSaved: Int
}
```

Quy tắc phân nhóm, tính từ một `TranslationRecord` đã `isSaved`, tại thời điểm `now`:

- `leech`: `ReviewPlanner.isLeech(lapses:)` đúng. Kiểm trước mọi nhóm khác, một thẻ chỉ thuộc một nhóm.
- `new`: `repetitions == 0 && lastReviewedAt == nil`.
- `due`: `dueDate == nil || dueDate <= now`.
- `learning`: `interval < 21` và chưa tới hạn.
- `mastered`: `interval >= 21` và chưa tới hạn.

`dayStreak` đếm lùi từ hôm nay theo ngày có ít nhất một `lastReviewedAt`; hôm nay chưa học thì vẫn
tính chuỗi tới hết hôm qua.

`Sources/translate/VocabDiscovery.swift`

```swift
enum VocabDiscovery {
    enum Level: String, CaseIterable { case a1, a2, b1, b2, c1, c2, unranked }
    struct Progress: Codable { var known: [String]; var skipped: [String] }

    static func level(of rendered: String) -> Level
    static func queue(entries: [VocabPackEntry], level: Level?, progress: Progress,
                      inStore: Set<String>) -> [VocabPackEntry]
}
```

`level(of:)` bắt CEFR từ dòng `Mức dùng: ... · A1` trong text đã dựng sẵn; không khớp thì `unranked`.
Phân bố hiện tại: B2 2228, chưa gắn 2219, B1 1573, A1 677, A2 438, C1 238, C2 37.

`queue(...)` trả về thứ tự duyệt: loại hết từ `known` và từ đã có trong store, sắp `unseen` trước
theo (level tăng dần, rồi alphabet), cuối cùng nối `skipped` vào đuôi. Đây là chỗ hiện thực yêu cầu
"bỏ qua thì lần sau xếp cuối".

### 3.3 Lưu trạng thái

`~/Library/Application Support/NTranslate/vocab-progress.json`:

```json
{ "version": 1, "known": ["ability"], "skipped": ["abdominal"] }
```

Ghi atomic (ghi file tạm rồi `replaceItemAt`), hỏng file thì bỏ qua và coi như rỗng, giống cách
`VocabPack.loadIfNeeded()` xử lý pack hỏng.

Ba giá trị của home lưu vào `config.json`: `reviewSessionLimit` (Int?, nil là tất cả),
`reviewQuestionKind` (String?, nil là Auto), `reviewFilter` (String?, nil là mọi thẻ).
Theo `CLAUDE.md`: khi đổi mặc định trong `AppConfig.default` phải cập nhật luôn
`~/Library/Application Support/NTranslate/config.json` trên máy đang dùng.

## 4. Màn hình

### 4.1 Home

- Vòng tròn phân nhóm Learning / Due / New / Mastered / Leech, số ở giữa là tổng due hôm nay.
  Bấm một nhóm là lọc phiên theo nhóm đó, bấm lại là bỏ lọc.
- Streak + heatmap 7 ngày, lấy từ `DeckStats.last7Days`.
- Chip mục tiêu: 10 thẻ / 20 thẻ / Tất cả. Chỉ cắt mảng `recordsToReview`, không đụng SRS.
- Sáu ô kiểu hỏi: Auto, Flip, Cloze, Recall, Listen, Contrast, mỗi ô một dòng mô tả. Thay
  `NSPopUpButton` hiện tại. Mode thẻ không hỗ trợ vẫn lùi về Flip kèm dòng nhắc, đúng như
  `ReviewPlanner.resolve(requested:...)` đang làm.
- Hàng nút: Start Review (N), Học từ mới, Reading Passage, Saved Passages.
- Kho rỗng thì ẩn Start và các nút review, giữ lại Học từ mới.

### 4.2 Phiên học

- Top bar cố định: home / undo / ẩn thẻ, thanh tiến độ chia đoạn xanh (đúng) và đỏ (sai),
  bộ đếm đúng / sai / còn lại / thời gian phiên.
- Hàng pill dưới top bar: kiểu hỏi đang chạy, nhóm thẻ, số lần lặp, lần ôn gần nhất.
- Thân thẻ giữ nguyên hành vi hiện có: term, nút đọc (4), đọc chậm (5), mở trong Translate (6),
  câu ví dụ, Read more, ô nhập, hai nút chọn của Contrast, dòng feedback.
- Nút chấm điểm hiện interval kế tiếp, tính bằng `ReviewPlanner.nextSchedule(grade:interval:ease:fuzz: 1.0)`.
  Fuzz 1.0 chỉ dùng để hiển thị; lúc chấm thật vẫn gọi `randomFuzz()` như hiện nay.
- Phím tắt giữ nguyên: Space lật, 1/2/3 chấm, Cmd+Z undo, Esc về home.

### 4.3 Tổng kết

- Bốn ô: độ chính xác, thời gian phiên, giây trung bình mỗi thẻ, số thẻ còn lại hôm nay.
- Danh sách thẻ sai trong phiên kèm số lần sai, lấy từ `missedTerms` và `relearnCounts`.
- Nút "Ôn lại N thẻ vừa sai": nạp đúng các thẻ đó vào một phiên practice, dùng lại đường
  `isPracticeMode` có sẵn.
- Nút "Tiếp tục M thẻ còn lại" khi mục tiêu phiên cắt ngắn deck.
- Thẻ chạm `ReviewPlanner.leechLapses` (8) hiện một dòng cảnh báo. Không tự ẩn, không tự đổi lịch.

### 4.4 Học từ mới

Vào từ nút trên home hoặc menu Study (Cmd+N).

- Đầu màn hình: bộ chọn cấp độ A1 / A2 / B1 / B2 / C1 / C2 / Chưa gắn / Tất cả, mỗi mục kèm số từ
  còn lại sau khi trừ `known` và các từ đã có trong store.
- Thân: từ tiếng Anh cỡ lớn, hai nút đọc (đọc thường, đọc chậm) dùng chung đường speech của
  cửa sổ review, và toàn bộ nội dung learn dựng sẵn của từ đó (`VocabPackEntry.r`) trong vùng cuộn.
- Ba nút hành động:
  - **Đã biết (1)**: thêm từ vào `known`, không tạo record, không bao giờ hiện lại.
  - **Học (2)**: tạo `TranslationRecord(mode: .learn, sourceText: w, resultText: r, isSaved: true, dueDate: now)`
    qua `historyStore.appendIfAbsent(...)`, đúng cách `PopoverController+Actions.swift:44` đang
    materialize một pack hit. Thẻ vào deck ngay, đếm luôn vào nhóm New của home.
  - **Bỏ qua (3)**: thêm từ vào `skipped`. Từ vẫn còn trong hàng đợi nhưng xếp sau mọi từ chưa gặp.
- Đếm tiến độ: "12 đã học · 5 đã biết · 3 bỏ qua · còn 657 từ A1".
- Hết hàng đợi thì hiện trạng thái rỗng kèm nút đổi cấp độ.

## 5. Menu bar và Dock

- `openReviewWindow` (`PopoverController+Menu.swift:215`) gọi `NSApp.setActivationPolicy(.regular)`
  **sau khi** cửa sổ Study đã `makeKeyAndOrderFront`, rồi `NSApp.activate(ignoringOtherApps: true)`.
- `windowWillClose` của cửa sổ Study trả về `.accessory`. Chỉ cửa sổ Study đổi policy; History và
  Settings không tự đổi, mở kèm Study thì hưởng menu bar sẵn có.
- Menu dựng thêm trong `buildMenu()`:
  - **NTranslate**: About NTranslate, Settings (Cmd+,), Check for Updates, Quit (Cmd+Q).
  - **Edit**: giữ nguyên.
  - **Study**: Start Review (Cmd+Return), Show Answer (Space), Again / Hard / Easy (Cmd+1/2/3),
    Undo Grade (Cmd+Z), Skip Card, Học từ mới (Cmd+N), Reading Passage (Cmd+R), Saved Passages.
  - **Window**: Minimize (Cmd+M), Close (Cmd+W), Zoom.
  - **Help**: Keyboard Shortcuts.
- Mục menu Study tự vô hiệu khi không ở trong phiên, qua `validateMenuItem`.
- `LSUIElement` trong `install-app.sh` giữ nguyên `true`: app vẫn khởi động không Dock icon.

### Rủi ro đã biết

Popup dịch là `NSPanel` non-activating. `NSApp.activate` lúc đổi policy có thể kéo focus khỏi
ứng dụng người dùng đang chọn chữ và làm mất selection đang chờ. Giảm rủi ro: chỉ đổi policy khi
cửa sổ Study thật sự hiện ra, và không đổi khi popup đang mở. Phải kiểm tay bằng
`Scripts/run-dev.sh`: mở popup, bôi chữ ở app khác, mở Study, đóng Study, kiểm tra popup vẫn
bắt được selection.

## 6. Kiểm chứng

Bắt buộc:

```bash
swift build

swiftc -parse-as-library Sources/translate/TranslationHistoryStore.swift \
  Sources/translate/ReviewPlanner.swift Sources/translate/LearnCard.swift \
  Sources/translate/DeckStats.swift Scripts/deck-stats-check.swift \
  -o /tmp/deck-stats-check && /tmp/deck-stats-check

swiftc -parse-as-library Sources/translate/VocabPack.swift \
  Sources/translate/VocabDiscovery.swift Scripts/vocab-discovery-check.swift \
  -o /tmp/vocab-discovery-check && /tmp/vocab-discovery-check
```

`deck-stats-check` phải phủ: một thẻ chỉ rơi vào một nhóm, leech thắng mọi nhóm khác, thẻ chưa
`dueDate` tính là due, chuỗi ngày không đứt khi hôm nay chưa học, chuỗi đứt khi nghỉ trọn một ngày.

`vocab-discovery-check` phải phủ: `known` bị loại hẳn, từ đã có trong store bị loại, `skipped`
nằm cuối hàng, thứ tự cấp độ tăng dần, `Mức dùng` thiếu thì rơi vào `unranked`.

Các check hiện có phải còn xanh: `speech-trim-check`, `tagged-response-check`, `vocab-pack-check`,
`learn-card-check`, `review-planner-check`.

`swift test` không dùng, lý do trong `CLAUDE.md`.

Kiểm tay sau khi `./install-app.sh`:

1. Mở Study, thấy tên NTranslate trên menu bar và Dock icon. Đóng Study, cả hai biến mất.
2. Bôi chữ ở app khác, mở popup, mở rồi đóng Study, popup vẫn dịch được selection mới.
3. Chọn nhóm Leech trên home, Start, phiên chỉ chứa thẻ leech.
4. Chọn mục tiêu 10 thẻ, phiên dừng đúng 10 thẻ và mở tổng kết có nút tiếp tục.
5. Học từ mới: Đã biết rồi khởi động lại app, từ đó không hiện lại. Bỏ qua rồi duyệt hết hàng,
   từ đó xuất hiện ở cuối. Bấm Học, thẻ có mặt trong deck và trong Translation History.

## 7. Thứ tự làm

1. `DeckStats` + check.
2. Tách ba view review, giữ nguyên hành vi và giao diện cũ, để `swift build` xanh trước khi đổi hình.
3. Home dashboard: vòng tròn, filter, chip mục tiêu, ô kiểu hỏi, lưu vào config.
4. Session view: top bar, pill, interval trên nút chấm điểm.
5. Summary view.
6. `VocabDiscovery` + check, rồi `NewWordsView`.
7. Activation policy và menu bar.
