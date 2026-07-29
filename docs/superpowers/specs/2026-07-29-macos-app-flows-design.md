# Thiết kế tài liệu luồng hoạt động NTranslate macOS

## Mục tiêu

Tạo `docs/macos-app-flows.md` mô tả toàn bộ chức năng người dùng và luồng nghiệp vụ của app macOS dựa trên source hiện tại.

## Đối tượng đọc

Người cần hiểu app làm gì và người dùng đi qua các bước nào, không cần biết Swift, class hoặc hàm nội bộ.

## Phạm vi

Tài liệu gồm:

1. Tổng quan app.
2. Khởi động và chạy nền trên menu bar.
3. Mở cửa sổ dịch bằng menu bar hoặc phím tắt.
4. Lấy nội dung từ vùng chọn hoặc clipboard.
5. Nhập, chỉnh sửa và dịch nội dung.
6. Chọn và đổi chiều ngôn ngữ.
7. Nghe phát âm nội dung nguồn và kết quả.
8. Sao chép kết quả.
9. Xem và quản lý lịch sử.
10. Thay đổi cài đặt.
11. Cấp quyền Accessibility.
12. Kiểm tra và cài cập nhật.
13. Thoát app.

Không mô tả source Windows, tên class/hàm, chi tiết triển khai Swift hoặc luồng dành riêng cho nhà phát triển.

## Cấu trúc

Tài liệu tổ chức theo hành trình người dùng. Mỗi chức năng có:

- mục đích;
- điểm bắt đầu;
- các bước nghiệp vụ bằng tiếng Việt tự nhiên;
- kết quả người dùng nhận được;
- sơ đồ Mermaid khi sơ đồ giúp luồng rõ hơn.

## Biểu đồ

- Một `flowchart` tổng quan liên kết các chức năng chính.
- `flowchart` cho luồng có quyết định như lấy nội dung, quyền Accessibility, lịch sử và cập nhật.
- `sequenceDiagram` cho phiên dịch chính, nơi tương tác giữa người dùng, app và dịch vụ cần thể hiện theo thời gian.
- Nhãn dùng thuật ngữ nghiệp vụ; không dùng symbol code.
- Sơ đồ giữ nhỏ, tránh gom toàn bộ app vào một biểu đồ khó đọc.

## Độ chính xác

Mọi mô tả phải đối chiếu source macOS hiện tại. Chỉ ghi hành vi có bằng chứng trong source. Hành vi lỗi chỉ nêu ở mức người dùng nhìn thấy nếu cần hiểu luồng chức năng.

## Kiểm tra

- File tồn tại đúng tại `docs/macos-app-flows.md`.
- Markdown có tiêu đề và mục lục chức năng rõ ràng.
- Mermaid dùng cú pháp hợp lệ, mỗi code fence đóng đủ.
- Bao phủ đủ 13 nhóm chức năng trong phạm vi.
- Không lẫn nội dung Windows hoặc chi tiết class/hàm.
- Không chạy installer vì thay đổi chỉ là tài liệu.
