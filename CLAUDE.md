## UI Language & Formatting

- Toàn bộ text hiển thị trên giao diện người dùng (UI text, menu bar, button, placeholder, label, alert, notification...) bắt buộc sử dụng **tiếng Anh**.
- Tuyệt đối **không sử dụng emoji** trên UI hoặc menu bar; sử dụng SF Symbols hoặc icon chuẩn macOS thay thế.

## Workflow

- Chỉ chạy `./install-app.sh` sau khi hoàn thành task có thay đổi source, resource, metadata, hoặc build/release script ảnh hưởng đến `NTranslate.app`.
- Không chạy script cho task chỉ đọc, phân tích, review, lập plan, hoặc chỉ sửa tài liệu; tránh build/install và bump version không cần thiết.
- Khi đã chạy script, luôn báo user version/build từ output để user test.
- Sau khi PR/feature/release đã merge thành công vào `main`, kiểm tra rồi xóa branch local/remote đã merge và worktree liên quan nếu sạch; không xóa branch chưa merge hoặc worktree có thay đổi chưa commit, chạy `git worktree prune`, và báo rõ mọi branch/worktree được giữ lại.
- Không bao giờ xóa branch local/remote `windows-app` khi cleanup branch/worktree. Đây là nhánh phát triển app Windows độc lập, tồn tại lâu dài và không merge vào `main`.
- Sinh tiếp gói từ vựng theo từng đợt bằng `./Scripts/vocab-daily.sh [số từ]` (mặc định 500). Script tự build generator khi nguồn đổi, chạy đợt mới rồi fold luôn `Resources/vocab-en-vi.json`; thẻ theo prompt cũ vẫn nằm trong gói cho tới ngày từ đó được sinh lại.
- `learnPrompt` và `weavePrompt` nằm trong `config.json`, và app đang chạy sẽ ghi đè cả file config từ bộ nhớ khi pin popup. Sửa prompt trong config phải làm lúc app đã tắt, hoặc dùng mục sync prompt trong Settings sau khi cài bản mới.
- Chạy bản debug bằng `./Scripts/run-dev.sh`, không chạy thẳng `.build/debug/translate`: script ký binary bằng cùng identity với app đã cài nên Keychain không hỏi lại password mỗi lần build.
- Verify code bằng `swift build`. Không chạy `swift test`: target test dùng swift-testing (`import Testing`) mà toolchain hiện tại không cung cấp, luôn fail với `no such module 'Testing'`.
- Khi sửa giá trị mặc định trong `AppConfig.default` (width, height, hotkey...), đồng thời cập nhật field tương ứng trong `~/Library/Application Support/NTranslate/config.json` trên máy user, vì config đã tồn tại sẽ giữ giá trị cũ và không tự nhận default mới.

## Test

- Verify mặc định là `swift build`. `swift test` không dùng được (lý do ở trên), nên logic không tầm thường đi kèm một self-check standalone trong `Scripts/`, chạy bằng `swiftc` chứ không qua test target.
- Chạy các check hiện có:

```bash
swiftc -parse-as-library Sources/translate/SpeechTrim.swift Scripts/speech-trim-check.swift \
  -o /tmp/speech-trim-check && /tmp/speech-trim-check

swiftc -parse-as-library Scripts/double-click-selection-check.swift \
  -o /tmp/dclick-check && /tmp/dclick-check

swiftc -parse-as-library Scripts/tagged-response-check.swift \
  -o /tmp/tagged-response-check && /tmp/tagged-response-check

swiftc -parse-as-library Sources/translate/VocabPack.swift Scripts/VocabWork.swift \
  Scripts/vocab-pack-check.swift -o /tmp/vocab-pack-check && /tmp/vocab-pack-check

swiftc -parse-as-library Sources/translate/LearnCard.swift Scripts/learn-card-check.swift \
  -o /tmp/learn-card-check && /tmp/learn-card-check

swiftc -parse-as-library Sources/translate/LearnCard.swift Sources/translate/ReviewPlanner.swift \
  Scripts/review-planner-check.swift -o /tmp/review-planner-check && /tmp/review-planner-check

swiftc -parse-as-library Sources/translate/TranslationHistoryStore.swift Sources/translate/ReviewPlanner.swift \
  Sources/translate/LearnCard.swift Sources/translate/DeckStats.swift Scripts/deck-stats-check.swift \
  -o /tmp/deck-stats-check && /tmp/deck-stats-check

swiftc -parse-as-library Sources/translate/VocabPack.swift Sources/translate/VocabDiscovery.swift \
  Scripts/vocab-discovery-check.swift -o /tmp/vocab-discovery-check && /tmp/vocab-discovery-check
```

- `double-click-selection-check` bắn chuột tổng hợp qua `CGEvent`, nên terminal đang chạy phải có quyền Accessibility. Check này fail cả khi bản có fix mất selection lẫn khi bản không fix bỗng chạy đúng (tức check hết tái hiện được bug).
- Muốn tái hiện lỗi tương tác chuột trong app thật thì dựng harness tạm: một file `Sources/translate/*Sim.swift` gọi từ `applicationDidFinishLaunching`, bật bằng biến môi trường, bắn `CGEvent` rồi log ra stderr. Gỡ sạch harness và mọi log tạm ngay khi tìm xong root cause, chỉ giữ lại check trong `Scripts/`.
- Đọc kết quả bằng `Scripts/run-dev.sh` thay vì `.build/debug/translate` để Keychain không hỏi password giữa chừng.

## SPDD

- Với yêu cầu từ GitHub Issue, tên mọi file SPDD phải dùng prefix `GITHUB-<github issue id>` thay cho `GGQPA-XXX`, ví dụ `GITHUB-17-202608081430-[Fix]-ui-popup-focus.md`.
- Với tài liệu gộp nhiều GitHub Issues, dùng `GITHUB-<id1>-<id2>-...` theo thứ tự ID tăng dần.
- Với yêu cầu không có GitHub Issue ID, dùng prefix `ISSUE-`; không thêm `XXX`, ví dụ `ISSUE-202608081444-[Feat]-release-macos-platform-update-isolation.md`.

## Release (DMG → GitHub Releases)

Khi user muốn đóng gói và/hoặc đăng bản build lên GitHub Releases, dùng:

```bash
./release-dmg.sh
```

Script sẽ:

1. Chạy `./install-app.sh` (bump patch version mặc định) trừ khi `SKIP_INSTALL=1`
2. Đóng gói app đã ký từ `/Applications/NTranslate.app` thành `dist/NTranslate-<version>-<arch>.dmg` (có shortcut Applications)
3. Cập nhật dòng **Latest:** trong `README.md` cho khớp version/DMG
4. Tạo GitHub Release + upload DMG (cần `gh` đã login) trừ khi `SKIP_UPLOAD=1`

### Quy định Release Notes và Changes Log
- **Mục "Điểm mới trong bản cập nhật (Changes log)"**: Bắt buộc diễn giải rõ ràng, dễ hiểu bằng **ngôn ngữ tự nhiên tiếng Việt** (tập trung vào tính năng mới, cải tiến, sửa lỗi từ góc nhìn người dùng), không để thô dạng danh sách git commit tiếng Anh ngắn củn.
- Phải có link so sánh chi tiết (`Full Changelog` / `So sánh chi tiết`) dạng `https://github.com/<repo>/compare/<last-tag>...<current-tag>`.
- Có thể chuẩn bị trước nội dung tiếng Việt vào file rồi truyền `NOTES_FILE=path.md ./release-dmg.sh`, hoặc sau khi release chạy lệnh `gh release edit <tag> --notes "..."` để cập nhật lại nội dung tiếng Việt chuẩn xác.

### Biến môi trường hữu ích

| Biến | Ý nghĩa |
| --- | --- |
| `VERSION_BUMP=patch\|minor\|major` | Truyền xuống `install-app.sh` (mặc định `patch`) |
| `SKIP_INSTALL=1` | Không build lại; dùng app đang có trong `/Applications` |
| `SKIP_UPLOAD=1` | Chỉ tạo DMG local, không gọi `gh release` |
| `DRAFT=1` | Tạo draft release trên GitHub |
| `NOTES_FILE=path.md` | Release notes tùy chỉnh (tiếng Việt) |

### Ví dụ

```bash
# Release đầy đủ (build + dmg + upload)
./release-dmg.sh

# Bump minor rồi release
VERSION_BUMP=minor ./release-dmg.sh

# Chỉ đóng gói DMG, không upload
SKIP_UPLOAD=1 ./release-dmg.sh

# Dùng bản đã cài sẵn, upload draft
SKIP_INSTALL=1 DRAFT=1 ./release-dmg.sh
```

Sau khi release xong: báo user URL release + version/build + tên file DMG và tóm tắt changes log bằng tiếng Việt so với bản gần nhất. Nếu `README.md` đổi, commit + push thay đổi đó cùng (nếu user đang yêu cầu publish).
