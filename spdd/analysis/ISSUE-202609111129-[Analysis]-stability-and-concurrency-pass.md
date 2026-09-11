# Rà soát ổn định và tận dụng concurrency

Ngày: 2026-09-11
Phạm vi: toàn bộ `Sources/translate` (19.899 dòng, 59 file)
Mục tiêu: giữ nguyên chức năng, cắt độ trễ cảm nhận được ở 3 đường đi nóng (khởi động, dịch, ôn tập)

## Tóm tắt

Code hiện tại sạch: không có `try!`, không `fatalError`, không force-unwrap nguy hiểm, event monitor và timer đều được gỡ đúng chỗ, `URLSession` streaming có `finishTasksAndInvalidate`. Selection reader đã chạy off-main và hiện panel trước khi đọc clipboard. Đó là phần đã tốt, không đụng vào.

Phần còn lại có 4 nhóm lãng phí đo được, xếp theo mức tác động:

| Nhóm | Vấn đề | Số đo |
| --- | --- | --- |
| A | Khởi động làm trùng việc: load config 3 lần, load history 2 lần, dựng 2 cửa sổ chưa ai mở | 2 lần quét toàn bộ `devices/` + 493 file audio |
| B | Mỗi lần dịch mở `URLSession` mới, bắt tay TLS lại từ đầu | 18-36 ms mỗi request (đo warm tới host đang cấu hình) |
| C | Mỗi chunk SSE chạy 5-8 lượt layout toàn văn bản | tăng tuyến tính theo độ dài, tổng chi phí bậc hai |
| D | Ghi history đọc, giải mã, mã hóa lại, ghi đè cả file tháng trên main thread | ~11 ms hiện tại (file 288 KB), mỗi lần chấm điểm SRS đều trả |

Phần E là các sai lệch quy ước (UI tiếng Việt), tách riêng để anh quyết.

---

## A. Khởi động

### A1. `AppConfig.load()` chạy 3 lần

`PopoverController.swift:158` (`var config = AppConfig.load()`), `:174` (`historyStore = TranslationHistoryStore(config: AppConfig.load())`), rồi `reloadConfig()` gọi `AppConfig.loadOutcome()` lần nữa. File config 21,8 KB, đọc và decode 3 lượt trước khi menu bar sẵn sàng.

Sửa: bỏ khởi tạo eager ở property, để `reloadConfig()` là nơi duy nhất dựng config và store.

### A2. `TranslationHistoryStore` load toàn bộ 2 lần

Store dựng lần đầu ở property initializer (`PopoverController.swift:174`), chạy trong `PopoverController()` ở `main.swift`, tức là **trước** `app.run()`. Sau đó `reloadConfig()` (`PopoverController+Menu.swift:455`) dựng lại store mới và vứt cái cũ. Mỗi lần init chạy `migrateLegacyHistoryIfNeeded()` cộng `load(pruning: true)`.

Thư mục history đang nằm trên ổ ngoài (`/Volumes/ESSD/MacData/NTranslateData`). Ổ ngủ hoặc chậm là khựng luôn lúc mở app.

Sửa: `historyStore` thành optional dựng một lần trong `reloadConfig()`.

### A3. Hai cửa sổ được dựng dù chưa ai mở

`historyWindowController` và `reviewWindowController` khai báo `lazy`, nhưng `applyTheme()` (`PopoverController.swift:382-383`) và `reviewWindowController.updateDependencies(...)` (`PopoverController+Menu.swift:472`) chạm vào chúng ngay trong `reloadConfig()` lúc launch. Thành ra `lazy` vô hiệu: toàn bộ UI của Review (1.900 dòng) và History (bảng, search field, segmented control) dựng lúc khởi động.

Cái timer 900 giây ở `PopoverController.swift:323` đã né đúng cách (`historyWindowController.window?.isVisible`), nhưng chỗ khác thì không.

Sửa: đổi sang `private var _reviewWindowController: ReviewWindowController?`, thêm accessor dựng khi cần. `applyTheme()` và `updateDependencies` chỉ chạm khi biến đã khác nil; lúc mở cửa sổ thì áp theme và dependency ngay tại chỗ.

### A4. Prune chạy đồng bộ trong init

`load(pruning: true)` gọi `pruneTombstones()` và `pruneOrphanAudio()`. Cái sau quét 493 file audio (8 MB) và đối chiếu với toàn bộ record. Không cần thiết phải xong trước khi menu bar hiện.

Sửa: `load(pruning:)` giữ nguyên phần đọc record (badge cần), tách 2 hàm prune ra một `Task.detached(priority: .utility)` chạy sau launch.

---

## B. Độ trễ mỗi lần dịch

### B1. Bắt tay TLS lại mỗi request

`Translator.swift:322` tạo `URLSession(configuration: .default, delegate: collector, delegateQueue: nil)` cho **từng** request streaming, rồi invalidate khi xong. Session mới nghĩa là connection pool mới, tức là DNS, TCP, TLS lại từ đầu.

Đo tới host đang cấu hình (`ninh-pc.tail1c92f0.ts.net`):

```
lần 1 (cold): connect=47ms  tls=84ms  total=95ms
lần 2 (warm): connect=5ms   tls=23ms  total=33ms
lần 3 (warm): connect=6ms   tls=25ms  total=34ms
```

Nghĩa là mỗi lần dịch đang trả thêm 25-85 ms trước khi byte đầu tiên về. Đường speech dùng `URLSession.shared` (`Translator.swift:847`) nên không dính.

Sửa: một `URLSession` streaming sống lâu dùng chung, delegate định tuyến callback theo `task.taskIdentifier`. Collector hiện tại giữ nguyên logic parse SSE, chỉ đổi chỗ sở hữu.

### B2. Vocab pack 9,7 MB decode trên MainActor

`VocabPack.loadIfNeeded()` chạy lần đầu khi bấm Learn, trong class `@MainActor`. Đo bản `-O`:

```
read   1 ms  (10.217.930 bytes)
decode 46 ms (7.410 entries)
index  0 ms
```

46 ms là một khung hình rưỡi bị mất, ngay đúng lúc user vừa bấm.

Sửa: `nonisolated static func decode` và `buildIndex` đã sẵn sàng để chạy off-main. Thêm `warm()` gọi từ một task nền sau launch, đẩy index đã dựng về MainActor. `loadIfNeeded()` giữ nguyên làm đường dự phòng nếu user bấm Learn trước khi warm xong.

### B3. Đọc audio đã lưu trên main thread

`PopoverController+Speech.swift:104` `hydrateStoredAudio` gọi `historyStore.audioData(for:kind:)` đồng bộ cho cả source lẫn result khi mở một record lịch sử. Đọc blob từ ổ ngoài trên main.

Sửa: đọc trong `Task.detached`, ghi vào `speechCache` qua `MainActor.run`, giống hệt cách `cacheSpeechTrim` đang làm.

---

## C. Độ mượt khi stream

### C1. 5 tới 8 lượt layout toàn văn bản mỗi chunk SSE

`StreamCollector` bắn `onPartial` theo từng chunk mạng, thường là từng token. Mỗi lần:

1. `appendStreamedResult` (`PopoverController+Status.swift:131`) gọi `setResultText`, dựng lại cả `NSAttributedString` và `setAttributedString` (một lượt layout của `textView`).
2. `throttleStreamReflow` (`:146`) gọi `measuredTextHeight`, hàm này dựng mới `NSTextStorage` + `NSTextContainer` + `NSLayoutManager` và `ensureLayout` toàn văn bản, **chỉ để quyết định có reflow hay không** (`PopoverLayoutMath.swift:4-14`).
3. Nếu quyết reflow, `reflowLayout()` đo tiếp: `currentPopoverHeight` tới `preferredPopoverHeight` tới `currentSplitPaneHeight` (2 lượt), rồi `layoutSplitPrism` gọi `measuredPrimaryPaneHeight` (2 lượt) cộng `measuredSubPaneHeight` (2) cộng `measuredQAPaneHeight` (1).

Văn bản dài dần nên tổng chi phí là bậc hai theo độ dài output. Đây là nguyên nhân số một khiến thẻ Learn dài stream giật.

Sửa (nhỏ nhất mà đủ): memo hóa `PopoverLayoutMath.measuredTextHeight` bằng một cache nhỏ khóa theo `(length, hash, width, fontSize)`. Cùng một chuỗi và cùng bề rộng thì trả kết quả cũ. Cắt 5-8 lượt layout xuống còn 1.

### C2. `lastStreamReflow` dùng chung cho main và sub

`PopoverController+Status.swift:163` so `now.timeIntervalSince(lastStreamReflow)` với một biến duy nhất cho cả hai pane. Khi main và subtranslate chạy song song, chúng cướp cửa sổ throttle của nhau: pane này reflow thì pane kia phải đợi thêm 100 ms.

Sửa: tách thành `lastStreamReflowMain` và `lastStreamReflowSub`.

### C3. `learnBadgeView.apply` chạy mỗi chunk

`setResultText` gọi `learnBadgeView.apply(to: value, live:)` (`:20`), hàm này quét lại toàn chuỗi tìm dòng `Mức dùng:`. Rẻ hơn layout nhiều, nên chỉ xử lý nếu sau C1 vẫn còn thấy trong trace. Ghi nhận, không sửa trước.

---

## D. Chỗ có thể chèn việc nền

Đây là phần anh hỏi: tận dụng lúc đang chờ.

### D1. Chuỗi warm sau khi launch

Ngay sau `applicationDidFinishLaunching`, có một khoảng dài user chưa bấm gì. Xếp vào đó, theo thứ tự ưu tiên, chạy trên `.utility`:

1. `VocabPack.warm()` (B2)
2. `VocabDiscovery.load()` (hiện đang đọc đồng bộ khi mở màn New words)
3. Prune history (A4)
4. `WeaveCache.list()` cho màn Passages

Cả 4 đều thuần Foundation, không đụng AppKit, nên đẩy off-main an toàn. Kết quả đẩy về MainActor một lần khi xong.

### D2. Lúc request đang bay

Một lần dịch mất 1-3 giây chờ mạng. Hiện tại `prefetchSpeech` cho phía source đã chạy song song với model call (`PopoverController+Actions.swift:89`), đúng bài. Ngoài ra khoảng đó đang để trống. Nếu chuỗi D1 chưa chạy xong thì đây là chỗ để nó tranh thủ, không cần thêm việc mới.

Bỏ qua: prefetch speech cho phía result khi câu đầu tiên xong. Đoán sai ranh giới câu là phí một request TTS, lợi không bù rủi ro.

### D3. Ghi history không chặn main

`persistRecordToMonthFile` (`TranslationHistoryStore.swift:770`) mỗi lần ghi đều: đọc lại cả file tháng, decode, xóa record trùng, append, sort toàn bộ, encode `prettyPrinted` + `sortedKeys`, ghi đè atomic, rồi `setAttributes`.

Đo trên file tháng hiện tại (`2026-09.json`, 295.491 bytes, 218 record) bằng `JSONSerialization`:

```
read   6 ms
decode 1 ms
encode 4 ms
write  0 ms
```

Khoảng 11 ms. `Codable` với `.iso8601` chậm hơn vài lần, và con số này tăng đều theo số record trong tháng. Một phiên ôn 20 thẻ trả nó 20 lần, mỗi lần ngay sau cú bấm chấm điểm.

Sửa: giữ danh sách record của tháng trong bộ nhớ (store đã có `records`), đẩy phần encode và ghi sang một serial queue nền, gộp các lần ghi liên tiếp cùng một `monthKey` (lần cuối thắng). `applyLocally` vẫn chạy đồng bộ nên UI thấy ngay. Ghi lại đồng bộ khi `applicationWillTerminate` để không mất dữ liệu.

Đây là thay đổi rủi ro nhất trong bản kế hoạch (đụng đường ghi dữ liệu), nên xếp cuối và có self-check riêng.

---

## E. Lệch quy ước (tách riêng, chờ anh quyết)

CLAUDE.md của project ghi: toàn bộ text hiển thị bắt buộc tiếng Anh. Hiện đang vi phạm ở:

- `NewWordsView.swift`: nhãn nút, tooltip, popup level, dòng tiến độ (khoảng 18 chuỗi)
- `ReviewHomeView.swift:76` `"due hôm nay"`, `:88` `"\(week[index]) thẻ"`, `:515` ghép `bucket.detail`
- `DeckStats.swift:24-30` `Bucket.detail` trả `"tới hạn ôn"`, `"đang thuộc dần"`, `"chưa học lần nào"`, `"đã thuộc"`, `"sai quá nhiều"`
- `LearnBadgeView.swift:94-100` `"Rất phổ biến"`, `"Phổ biến"`, `"Ít gặp"` (cái này bám theo output prompt tiếng Việt, đổi thì phải đổi cả prompt)

Không đụng trong đợt này trừ khi anh nói có. Nó không ảnh hưởng ổn định, và `LearnBadgeView` dính vào prompt nên là một task riêng đúng nghĩa.

---

## Các giai đoạn

Mỗi giai đoạn build sạch và test được độc lập. Dừng ở bất kỳ giai đoạn nào cũng để lại app chạy được.

### Giai đoạn 1: dọn khởi động (A1, A2, A3)

Chỉ sửa thứ tự và quyền sở hữu, không đổi logic.

- `PopoverController.swift`: `config` và `historyStore` bỏ khởi tạo eager
- `PopoverController.swift`: `historyWindowController`, `reviewWindowController` chuyển sang optional cộng accessor
- `PopoverController.swift:382` `applyTheme()` chỉ áp cho cửa sổ đã tồn tại
- `PopoverController+Menu.swift`: `reloadConfig()` là nơi duy nhất dựng store, `updateDependencies` chỉ gọi khi review window đã dựng

Verify: `swift build`, mở app, kiểm tra menu bar hiện, mở History và Review thấy đúng theme và đúng dữ liệu.

### Giai đoạn 2: memo hóa đo văn bản (C1, C2)

- `PopoverLayoutMath.swift`: thêm cache cho `measuredTextHeight`
- `PopoverController+Status.swift`: tách `lastStreamReflow` theo scope

Verify: `swift build`, cộng self-check mới `Scripts/layout-measure-cache-check.swift` khẳng định cache trả đúng giá trị khi đổi bề rộng, đổi nội dung, đổi cỡ chữ (TextZoom).

### Giai đoạn 3: dùng lại kết nối và warm nền (B1, B2, B3, D1)

- `Translator.swift`: một session streaming dùng chung, delegate định tuyến theo `taskIdentifier`
- `VocabPack.swift`: thêm `warm()` chạy off-main
- `PopoverController+Speech.swift`: `hydrateStoredAudio` đọc off-main
- `PopoverController.swift`: chuỗi warm sau launch
- `TranslationHistoryStore.swift`: prune tách khỏi init (A4)

Verify: `swift build`, cộng self-check `Scripts/stream-session-check.swift` cho phần định tuyến delegate nhiều task song song. Chạy `Scripts/run-dev.sh`, dịch 3 lần liên tiếp, đọc log timing xem thời gian tới byte đầu có giảm.

### Giai đoạn 4: ghi history nền (D3)

- `TranslationHistoryStore.swift`: cache theo tháng, serial write queue, gộp ghi, flush khi thoát

Verify: `swift build`, self-check `Scripts/history-write-queue-check.swift` khẳng định ghi liên tiếp cùng tháng gộp lại và kết quả trên đĩa khớp với bộ nhớ. Chạy thủ công một phiên ôn 10 thẻ rồi tắt app, mở lại kiểm tra đủ điểm SRS.

### Sau cùng

Chạy lại toàn bộ self-check hiện có trong CLAUDE.md, rồi `./install-app.sh` và báo version.

## Không làm trong đợt này

- Đổi UI sang tiếng Anh (phần E), chờ anh quyết
- Lazy load history theo 3 tháng gần nhất: ghi chú `ponytail` trong code nói chờ tới khi RAM thành vấn đề, hiện 218 record một tháng nên chưa tới
- Prefetch speech phía result theo ranh giới câu (D2), rủi ro hơn lợi
- Đụng vào `SelectionReader`, phần này đã off-main và đã tối ưu đúng
