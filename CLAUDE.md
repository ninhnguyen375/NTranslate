## UI Language & Formatting

- Toàn bộ text hiển thị trên giao diện người dùng (UI text, menu bar, button, placeholder, label, alert, notification...) bắt buộc sử dụng **tiếng Anh**.
- Tuyệt đối **không sử dụng emoji** trên UI hoặc menu bar; sử dụng SF Symbols hoặc icon chuẩn macOS thay thế.

## Workflow

- Chỉ chạy `./install-app.sh` sau khi hoàn thành task có thay đổi source, resource, metadata, hoặc build/release script ảnh hưởng đến `NTranslate.app`.
- Không chạy script cho task chỉ đọc, phân tích, review, lập plan, hoặc chỉ sửa tài liệu; tránh build/install và bump version không cần thiết.
- Khi đã chạy script, luôn báo user version/build từ output để user test.
- Sau khi PR/feature/release đã merge thành công vào `main`, kiểm tra rồi xóa branch local/remote đã merge và worktree liên quan nếu sạch; không xóa branch chưa merge hoặc worktree có thay đổi chưa commit, chạy `git worktree prune`, và báo rõ mọi branch/worktree được giữ lại.
- Không bao giờ xóa branch local/remote `windows-app` khi cleanup branch/worktree. Đây là nhánh phát triển app Windows độc lập, tồn tại lâu dài và không merge vào `main`.
- Verify code bằng `swift build`. Không chạy `swift test`: target test dùng swift-testing (`import Testing`) mà toolchain hiện tại không cung cấp, luôn fail với `no such module 'Testing'`.
- Khi sửa giá trị mặc định trong `AppConfig.default` (width, height, hotkey...), đồng thời cập nhật field tương ứng trong `~/Library/Application Support/NTranslate/config.json` trên máy user, vì config đã tồn tại sẽ giữ giá trị cũ và không tự nhận default mới.

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
