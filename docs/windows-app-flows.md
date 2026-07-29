# Luồng hoạt động của NTranslate trên Windows

Tài liệu mô tả chức năng và luồng nghiệp vụ của NTranslate trên Windows theo góc nhìn người dùng. Nội dung phản ánh hành vi hiện có trong source Windows sau các thay đổi popup parity Task 1–5.

## Mục lục

1. [Tổng quan](#1-tổng-quan)
2. [Khởi động và chạy nền](#2-khởi-động-và-chạy-nền)
3. [Mở và đóng cửa sổ dịch](#3-mở-và-đóng-cửa-sổ-dịch)
4. [Lấy nội dung cần dịch](#4-lấy-nội-dung-cần-dịch)
5. [Dịch văn bản hoặc hình ảnh](#5-dịch-văn-bản-hoặc-hình-ảnh)
6. [Chọn và đổi chiều ngôn ngữ](#6-chọn-và-đổi-chiều-ngôn-ngữ)
7. [Học từ hoặc câu](#7-học-từ-hoặc-câu)
8. [Nghe phát âm](#8-nghe-phát-âm)
9. [Sao chép kết quả](#9-sao-chép-kết-quả)
10. [Xem và quản lý lịch sử](#10-xem-và-quản-lý-lịch-sử)
11. [Thay đổi cài đặt](#11-thay-đổi-cài-đặt)
12. [Lấy vùng chọn bằng UI Automation](#12-lấy-vùng-chọn-bằng-ui-automation)
13. [Kiểm tra và cài cập nhật](#13-kiểm-tra-và-cài-cập-nhật)
14. [Thoát ứng dụng](#14-thoát-ứng-dụng)

## 1. Tổng quan

NTranslate là ứng dụng chạy nền trong khay hệ thống Windows. Người dùng có thể mở popup dịch thủ công từ biểu tượng khay hoặc nhấn phím tắt toàn cục để ứng dụng lấy nội dung hiện tại và tự bắt đầu dịch.

Nội dung đầu vào có thể là văn bản vùng chọn, văn bản từ thao tác mô phỏng **Copy**, văn bản clipboard hoặc hình ảnh clipboard. Popup dùng bố cục hai vùng cạnh nhau: nguồn ở bên trái, kết quả ở bên phải. Kết quả có thể được nghe, sao chép, đánh dấu và mở lại từ lịch sử.

## 2. Khởi động và chạy nền

1. Ứng dụng đọc cấu hình từ `%LOCALAPPDATA%\NTranslate\config.json`; khi file không tồn tại, ứng dụng dùng cấu hình mặc định.
2. Ứng dụng khởi tạo dịch vụ clipboard, UI Automation, phím tắt toàn cục, biểu tượng khay, lịch sử, giọng nói, cài đặt và cập nhật.
3. Cửa sổ dịch được kích hoạt một lần để khởi tạo rồi ẩn ngay bằng `AppWindow.Hide()`. Khởi động bình thường không để popup hiển thị.
4. Ứng dụng thêm biểu tượng khay và đăng ký phím tắt toàn cục.
5. Nếu cấu hình không đọc được, sai định dạng hoặc không hợp lệ, ứng dụng dùng giá trị mặc định và giữ hướng dẫn lỗi để hiển thị trong popup. Lỗi đăng ký phím tắt cũng được đưa vào hướng dẫn này.
6. Nếu bật **Start with Windows**, đăng ký khởi động cùng Windows được áp dụng qua luồng lưu cài đặt.

Menu khay cung cấp **Open Translator**, **Translation History**, **Settings**, **Check for Updates**, **Start with Windows** và **Exit**.

## 3. Mở và đóng cửa sổ dịch

Người dùng có hai luồng mở popup:

- nhấp biểu tượng khay hoặc chọn **Open Translator** để mở thủ công với vùng nhập trống;
- nhấn phím tắt toàn cục để lấy nội dung rồi tự dịch nếu có văn bản hoặc hình ảnh hợp lệ.

Popup được đặt gần vị trí con trỏ, giới hạn trong vùng làm việc của màn hình gần nhất và được đưa lên trước. Bố cục chia đôi hiển thị nội dung nguồn bên trái, kết quả chỉ đọc bên phải; thanh đầu có nút cập nhật, lịch sử, ghim và đóng.

Popup tự ẩn khi mất kích hoạt nếu chưa ghim. Bật nút ghim giữ popup khi chuyển sang cửa sổ khác. Nút đóng, phím **Escape** hoặc nút đóng cửa sổ chỉ ẩn popup và hủy công việc đang chạy; ứng dụng vẫn chạy trong khay. Chỉ luồng **Exit** mới đóng tiến trình.

## 4. Lấy nội dung cần dịch

Khi người dùng nhấn phím tắt toàn cục, ứng dụng tìm nội dung theo thứ tự:

1. Đọc văn bản đang được chọn từ phần tử đang có focus bằng Windows UI Automation `TextPattern.GetSelection()`.
2. Nếu không có văn bản và **Simulate copy** đang bật, gửi lệnh **Ctrl+C**, chờ clipboard đổi tối đa 250 ms rồi đọc văn bản Unicode mới.
3. Nếu lệnh **Ctrl+C** gửi thành công nhưng không tạo văn bản dùng được, hoặc **Simulate copy** tắt, đọc clipboard hiện tại: ưu tiên văn bản Unicode, sau đó hình ảnh được mã hóa thành PNG.
4. Nếu gửi lệnh **Ctrl+C** lỗi hoặc không có nội dung hợp lệ, capture thất bại và ứng dụng mở popup thủ công để người dùng nhập.

Luồng mô phỏng **Copy** chụp clipboard để theo dõi sequence number nhưng không khôi phục nội dung clipboard cũ. Nội dung vừa được ứng dụng khác sao chép được giữ lại. Đây là khác biệt có chủ ý so với luồng macOS: Windows không ghi đè clipboard bằng snapshot cũ sau khi **Ctrl+C**, tránh rollback đè lên thay đổi clipboard phát sinh trong lúc capture.

Mỗi yêu cầu capture mới hủy yêu cầu trước. Kết quả capture cũ không được mở hoặc dịch nếu đã có yêu cầu mới hơn.

## 5. Dịch văn bản hoặc hình ảnh

### Dịch văn bản

1. Người dùng nhập văn bản hoặc nhận văn bản từ luồng capture.
2. Khi mở thủ công, người dùng bấm **Translate** hoặc nhấn **Ctrl+Enter**. Khi mở bằng phím tắt với văn bản hợp lệ, popup hiển thị và tự bắt đầu dịch.
3. Ứng dụng từ chối nội dung rỗng hoặc dài hơn giới hạn cấu hình.
4. Ứng dụng xác định cặp ngôn ngữ hiệu lực, chọn prompt dịch hoặc ngữ pháp, rồi gửi yêu cầu đến API đã cấu hình.
5. Trong lúc xử lý, popup hiển thị progress. Yêu cầu cũ bị hủy hoặc bỏ kết quả nếu nội dung, ngôn ngữ, cửa sổ hay yêu cầu mới làm nó hết hiệu lực.
6. Khi thành công, kết quả xuất hiện ở vùng bên phải, được ghi vào lịch sử và có thể tự sao chép nếu **Auto-copy** đang bật.
7. Khi thất bại, popup giữ nội dung nguồn và hiển thị lỗi.

Nếu ngôn ngữ nguồn và đích dẫn đến cùng ngôn ngữ, luồng **Translate** chọn prompt kiểm tra ngữ pháp.

### Dịch hình ảnh

Hình ảnh có hai đường vào:

- phím tắt lấy được hình ảnh clipboard: popup chuyển sang chế độ ảnh và tự bắt đầu dịch;
- nút **Clipboard** trong popup: đọc bitmap hiện tại, hiển thị preview rồi bắt đầu dịch.

Ảnh được chuẩn hóa thành PNG trước khi gửi. Chế độ ảnh ẩn ô nhập nguồn, hiển thị preview, khóa chọn ngôn ngữ nguồn, tắt **Learn** và tắt phát âm nguồn. Kết quả văn bản vẫn có thể nghe, sao chép, tự sao chép và ghi lịch sử.

## 6. Chọn và đổi chiều ngôn ngữ

- Popup có bộ chọn ngôn ngữ nguồn và đích ở thanh dưới.
- Chế độ **Auto detect** suy ra ngôn ngữ nguồn từ văn bản khi tạo yêu cầu và hiển thị mã ngôn ngữ nguồn trên pane.
- Nút đổi chiều chỉ hoạt động khi ngôn ngữ nguồn hiện tại có trong danh sách ngôn ngữ đích; thao tác này hoán đổi hai lựa chọn.
- Thay đổi nội dung nguồn hoặc ngôn ngữ hủy yêu cầu và audio cũ, xóa kết quả cũ, tránh áp dụng phản hồi không còn đúng.
- Trong chế độ ảnh, lựa chọn ngôn ngữ nguồn bị khóa; người dùng vẫn chọn ngôn ngữ đích.

Source hiện tại không tự chuyển nội dung kết quả thành nội dung nguồn khi đổi chiều.

## 7. Học từ hoặc câu

1. Người dùng nhập hoặc capture văn bản nguồn.
2. Người dùng bấm **Learn** hoặc nhấn **Ctrl+Shift+L**.
3. Ứng dụng kiểm tra nội dung rỗng và giới hạn độ dài giống luồng dịch văn bản.
4. Ứng dụng chọn prompt học theo nội dung và cặp ngôn ngữ rồi gửi yêu cầu.
5. Kết quả học hiển thị trong pane kết quả.

Kết quả **Learn** không được ghi vào lịch sử bởi history sink hiện tại, nhưng vẫn có thể sao chép và nghe phần kết quả. Chức năng **Learn** bị tắt trong chế độ ảnh.

Nút **Images** tạo truy vấn tìm kiếm ngắn từ nội dung nguồn, dùng chính nội dung làm fallback nếu tạo truy vấn thất bại, rồi mở Google Images trong trình duyệt mặc định.

## 8. Nghe phát âm

Popup có nút phát âm riêng cho nguồn và kết quả, cùng bộ chọn tốc độ từ 0,5 đến 1,5.

- Lần phát đầu tải audio từ API giọng nói, kiểm tra dữ liệu rồi phát bằng player Windows.
- Audio đã tải được giữ trong cache theo kênh, văn bản và model.
- Cùng nút chuyển giữa tải, phát, tạm dừng, tiếp tục và thử lại; tên accessible của nút phản ánh hành động hiện tại.
- Đổi tốc độ cập nhật player đang dùng.
- Khi bản dịch có record lịch sử, audio nguồn hoặc kết quả được gắn vào record tương ứng để cửa sổ lịch sử có thể phát lại.
- Thay đổi nội dung/ngôn ngữ hoặc đóng popup hủy audio không còn phù hợp. Khi popup chưa ghim, mất kích hoạt sẽ tự ẩn và hủy công việc popup/audio; khi đã ghim, mất kích hoạt giữ popup và công việc đang chạy. Việc chỉ bắt đầu một yêu cầu dịch mới không tự hủy audio.
- Chế độ ảnh không cho phát âm nguồn; kết quả ảnh vẫn có thể phát âm.

Nếu **Auto-prefetch speech** bật, ứng dụng tải trước audio nguồn và kết quả sau bản dịch văn bản thành công.

## 9. Sao chép kết quả

Người dùng có thể:

- bấm nút copy trong pane kết quả;
- nhấn **Ctrl+Shift+C**;
- bật **Auto-copy** để tự ghi kết quả thành công vào clipboard.

Copy chỉ khả dụng khi popup đang ở trạng thái kết quả và kết quả không rỗng. Hướng dẫn, trạng thái loading, lỗi và phản hồi cũ không được sao chép. Nếu clipboard không ghi được, popup hiển thị `Clipboard unavailable. Try Copy again.`

## 10. Xem và quản lý lịch sử

Bản dịch văn bản và hình ảnh thành công được lưu với ID, thời gian, văn bản nguồn, kết quả, ngôn ngữ nguồn/đích, đường dẫn audio nguồn/kết quả và trạng thái đã lưu.

Người dùng có thể:

- mở lịch sử từ menu khay hoặc nút trên popup;
- xem record mới nhất trước;
- tìm theo nội dung nguồn hoặc kết quả;
- lọc **All history** hoặc **Saved**;
- lọc theo toàn bộ thời gian, hôm nay, 24 giờ, tuần hoặc tháng;
- đánh dấu/bỏ đánh dấu từ popup hoặc cửa sổ lịch sử;
- phát audio nguồn/kết quả đã gắn;
- xóa một record hoặc xóa toàn bộ record đang hiển thị sau xác nhận;
- nhấp đúp hoặc nhấn **Enter** để mở lại record trong popup.

Nếu history store có lỗi tải, cửa sổ hiển thị lỗi và khóa thao tác thay đổi dữ liệu.

### Giới hạn metadata lịch sử ảnh

Record lịch sử hiện tại chỉ có trường văn bản và đường dẫn audio; không có trường lưu bytes ảnh, đường dẫn ảnh, MIME type hoặc cờ phân biệt loại nguồn. Vì vậy bản dịch ảnh được lưu với source text cố định `Clipboard image`, nhưng ảnh gốc và preview không được lưu. Mở lại record này phục hồi như record văn bản với nhãn `Clipboard image`, không phục hồi chế độ ảnh hay hình ảnh gốc.

## 11. Thay đổi cài đặt

Cửa sổ **Settings** chia thành **General**, **Prompts**, **Languages** và **Advanced**. Các thiết lập hiện có gồm:

- API key trong Windows Credential Locker, API base URL và speech API URL;
- model, prompt dịch, học câu/từ và ngữ pháp;
- ngôn ngữ nguồn, đích, bản địa và danh sách ngôn ngữ;
- model giọng nói, tốc độ và tự tải trước audio;
- **Auto-copy**, **Simulate copy**, **Start with Windows**;
- thư mục lịch sử, phím tắt, giới hạn độ dài, chiều rộng và chiều cao popup.

Khi lưu, ứng dụng kiểm tra cấu hình, tốc độ và đường dẫn tuyệt đối. Luồng lưu chuẩn bị chuyển lịch sử nếu đổi thư mục, lưu API key, lưu config, commit chuyển lịch sử rồi áp dụng cấu hình runtime và đăng ký khởi động cùng Windows. Nếu một bước thất bại, coordinator cố rollback config, API key và chuyển lịch sử; cửa sổ giữ mở và hiển thị lỗi.

**Revert** khôi phục snapshot đã tải. **Cancel** đóng cửa sổ mà không chạy luồng lưu. Menu khay cũng cho phép bật/tắt nhanh **Start with Windows** qua cùng coordinator lưu cài đặt.

## 12. Lấy vùng chọn bằng UI Automation

Windows không có luồng yêu cầu quyền Accessibility tương ứng macOS. Ứng dụng dùng Windows UI Automation:

1. Lấy `AutomationElement.FocusedElement`.
2. Yêu cầu `TextPattern` từ phần tử đang focus.
3. Đọc tất cả range do `GetSelection()` trả về và nối văn bản.
4. Nếu phần tử không hỗ trợ `TextPattern`, không có selection hoặc UI Automation lỗi, chuyển sang mô phỏng **Ctrl+C** hay clipboard theo cấu hình.

Source không triển khai màn hình xin quyền riêng cho UI Automation. Khả năng đọc trực tiếp phụ thuộc ứng dụng đang focus có cung cấp `TextPattern` và selection hay không. Người dùng vẫn có thể dùng **Simulate copy**, clipboard hoặc nhập trực tiếp khi UI Automation không lấy được nội dung.

## 13. Kiểm tra và cài cập nhật

Người dùng mở luồng cập nhật từ menu khay hoặc nút trên popup.

1. Ứng dụng đọc các release GitHub của `ninhnguyen375/NTranslate`.
2. Policy bỏ qua draft, prerelease, tag không phải semantic version và phiên bản không mới hơn bản đang chạy.
3. Release chỉ hợp lệ khi có đúng một asset tên `NTranslate-<version>-win-x64.msix`.
4. Nếu không có bản mới, kiểm tra thủ công báo `NTranslate is up to date.`
5. Nếu có bản mới, dialog hiển thị trạng thái và release notes để người dùng chọn cài.
6. Ứng dụng tải MSIX vào `%TEMP%\NTranslate\Updates`, xác minh package và kiểm tra version package trùng release đã chọn.
7. Sau xác minh, ứng dụng mở đường dẫn MSIX bằng Windows Shell với `UseShellExecute = true`.

Bước cuối là handoff cho trình cài đặt MSIX của Windows. Source không tự thay file ứng dụng, không tự thoát và không tự khởi động lại sau cập nhật. Lỗi kiểm tra, xác minh hoặc mở installer được hiển thị qua trạng thái cập nhật/hướng dẫn popup.

## 14. Thoát ứng dụng

1. Người dùng chọn **Exit** từ menu khay.
2. Ứng dụng hủy capture, request dịch và audio đang chạy.
3. Ứng dụng gỡ đăng ký phím tắt, xóa biểu tượng khay và khôi phục window procedure nếu cần.
4. Ứng dụng tháo crash handlers, dispose history/audio, đóng cửa sổ lịch sử, cài đặt và popup.
5. Shutdown chỉ chạy một lần; các bước còn lại vẫn được thử nếu một bước ném lỗi, sau đó lỗi được gom lại.

Đóng hoặc làm mất focus popup không thoát ứng dụng. NTranslate tiếp tục chạy trong khay cho đến khi người dùng chọn **Exit** hoặc tiến trình bị hệ thống kết thúc.
