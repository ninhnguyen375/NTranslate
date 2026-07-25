# Auto-Update via GitHub Releases Design Spec

## Executive Summary
Thêm chức năng kiểm tra và tự động cập nhật phiên bản mới cho NTranslate từ GitHub Releases (`ninhnguyen375/NTranslate`).
Cơ chế: Tự động kiểm tra khi khởi động app + nút "Check for Updates" thủ công trong menu popover. Tự động tải DMG, mount, cài đặt đè vào `/Applications/NTranslate.app` và khởi động lại app.

## Architecture & Data Flow

### 1. UpdateManager Service (`Sources/translate/UpdateManager.swift`)
- **Check for updates:**
  - Gọi GitHub REST API: `https://api.github.com/repos/ninhnguyen375/NTranslate/releases/latest`
  - Đọc `tag_name` (e.g. `v1.0.3`) và danh sách `assets`.
  - Tìm asset `.dmg` (URL download: `browser_download_url`).
- **Version comparison:**
  - So sánh `tag_name` (bỏ `v` prefix) với `CFBundleShortVersionString` của Bundle hiện tại.
  - Sử dụng so sánh SemVer cơ bản (Numeric comparison theo từng component major.minor.patch).
- **Download & Installation:**
  - Tải DMG về `NSTemporaryDirectory()`.
  - Mount DMG qua `hdiutil attach -nobrowse <dmgPath>`.
  - Tìm `NTranslate.app` trong volume mount.
  - Chạy một background shell process (hoặc script rời/detached process) để:
    1. Chờ app chính thoát (`kill` / `pkill` hoặc check PID).
    2. Copy/ditto `NTranslate.app` mới đè vào `/Applications/NTranslate.app`.
    3. Unmount DMG qua `hdiutil detach`.
    4. Mở app mới: `open /Applications/NTranslate.app`.
    5. Xóa file DMG tạm.
  - Gọi `NSApp.terminate(nil)` để app hiện tại thoát an toàn.

### 2. UI Integration (`Sources/translate/PopoverController.swift`)
- **Popover Header/Menu:**
  - Thêm nút "Check for Updates" (biểu trưng mũi tên xoay / spark / update icon) ở thanh công cụ hoặc menu của Popover.
- **Update Dialog / Notification Alert:**
  - Khi tìm thấy bản update: Hiển thị NSAlert với thông tin phiên bản mới (`tag_name`) và Release Notes (`body`).
  - Nút "Update & Restart": Gọi `UpdateManager.shared.downloadAndInstall(...)`.
  - Nút "Skip / Later": Đóng alert.
  - Khi kiểm tra thủ công và không có update: Hiển thị alert "You're up to date!".
- **Auto Check on Launch:**
  - Thực hiện kiểm tra ngầm sau 3-5 giây khi app khởi chạy. Nếu có bản mới thì hiển thị banner/alert thông báo.

## Edge Cases & Error Handling
- **Không có kết nối Internet / GitHub API error:** Báo lỗi nhẹ nhàng nếu check thủ công, im lặng bỏ qua nếu check tự động.
- **Không tìm thấy file DMG trong Release assets:** Báo lỗi không tìm thấy bộ cài đặt.
- **Lỗi cấp quyền / Access permissions khi ghi vào `/Applications`:** Trợ giúp bằng script hoặc báo lỗi nếu không ghi được.

## Verification & Testing Strategy
1. **Unit Test for Version Comparison:**
   - Test logic so sánh phiên bản: `1.0.2` < `1.0.3`, `1.0.2` == `1.0.2`, `1.1.0` > `1.0.9`.
2. **Integration / Manual Test:**
   - Mock response của GitHub release hoặc test với tag thực tế.
   - Build và test script update tự động thay thế app trong `/Applications`.
