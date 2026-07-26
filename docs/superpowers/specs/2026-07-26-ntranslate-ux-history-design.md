# NTranslate UX, History và Translation Actions Design

**Ngày:** 2026-07-26

## Mục tiêu

Hoàn thiện các thao tác quanh bản dịch, sửa lỗi swap ngôn ngữ và nâng cấp riêng cửa sổ History theo phong cách Liquid Glass hiện có của popup Translate.

## Phạm vi

- Luôn cho phép lưu mọi kết quả dịch hợp lệ, kể cả sau thao tác Learn.
- Xóa từng record và xóa toàn bộ phần dữ liệu đang xem trong History hoặc Saved Words, có xác nhận khi xóa hàng loạt.
- Redesign riêng cửa sổ History; popup Translate chỉ bổ sung control được yêu cầu.
- Giữ text dài trong History không chèn hoặc đẩy cụm nút.
- Lọc History theo Today, 24h, Week, Month.
- Double-click record để nạp nguyên trạng vào popup Translate, không gọi dịch lại.
- Thêm Images để LLM tạo truy vấn ngắn, trực quan rồi mở Google Images; fallback sang source text khi LLM lỗi.
- Thêm tốc độ speech dùng chung từ 0.5x đến 1.5x, bước 0.1x, ghi nhớ bằng UserDefaults.
- Swap cả source/result text và ngôn ngữ; với Auto detect, dùng ngôn ngữ đã detect trước khi swap.

## Kiến trúc

Giữ kiến trúc AppKit hiện tại và mở rộng đúng điểm dùng chung:

- `TranslationHistoryStore`: thêm thao tác xóa record và xóa tập record, đồng thời dọn audio tương ứng sau khi JSON đã persist thành công.
- `HistoryWindowController`: quản lý tab History/Saved Words, time filter, layout Liquid Glass, icon actions, xác nhận xóa hàng loạt và callback mở record.
- `PopoverController`: nhận callback mở record, lưu kết quả chưa có record, Images, speech rate và swap đầy đủ.
- `Translator`: thêm request tạo image-search query bằng cùng cấu hình LLM hiện tại; không thêm dependency hoặc service abstraction mới.
- Logic thuần cho time filtering và swap được đặt ở type hiện có phù hợp để test không cần dựng UI.

## History Liquid Glass

Cửa sổ History dùng vật liệu, độ trong, góc bo và icon SF Symbols đồng điệu popup Translate:

- Shell bo góc 22pt, visual effect material và nền trong suốt.
- Thanh trên gồm search, segmented History/Saved Words, segmented Today/24h/Week/Month và icon clear.
- Mỗi record là một surface bo góc 16pt. Metadata ở trên, source/result ở giữa, action icons cố định bên phải.
- Text source/result dùng một dòng truncating tail để không chèn nút. Full text vẫn có accessibility label và tooltip.
- Icon actions: play source/result nếu có audio, save/unsave và delete. Double-click toàn row mở popup Translate.
- Xóa từng dòng thực hiện ngay. Clear visible hiện cảnh báo xác nhận và chỉ xóa record thuộc tab cùng time filter hiện tại; query search cũng giới hạn tập bị xóa.

## Lọc thời gian

Các mốc dùng `Calendar.current` và thời điểm hiện tại:

- Today: từ `startOfDay(for: now)`.
- 24h: từ `now - 24 hours`.
- Week: từ `now - 7 days`.
- Month: từ `now - 1 month` theo Calendar.

Search, tab Saved Words và time range kết hợp bằng phép AND. Record giữ thứ tự mới nhất trước.

## Save và Learn

Nút Save được bật khi source/result hiện tại đều có nội dung và không có request đang chạy:

- Nếu `currentRecordID` trỏ tới record khớp nội dung, toggle `isSaved`.
- Nếu chưa có record hoặc record không còn khớp, tạo `TranslationRecord` mới với `isSaved = true`, dùng cặp ngôn ngữ đã resolve.
- Learn không vô hiệu hóa Save. Nếu Learn thay đổi UI state, source/result hiện hành vẫn đủ để tạo hoặc cập nhật record.

## Mở lại record

`HistoryWindowController` phát callback chứa `TranslationRecord`. `PopoverController`:

1. Hiện và focus popup Translate.
2. Nạp source/result text.
3. Chọn source/target từ record.
4. Gán `currentRecordID` để Save/Unsave tác động đúng record.
5. Dừng speech/request cũ và reflow layout.

Không gọi LLM và không tạo record mới.

## Images

Images dùng source text hiện tại. `Translator` yêu cầu LLM trả về duy nhất truy vấn Google Images ngắn, cụ thể, ưu tiên đối tượng thực tế và bỏ giải thích. Ví dụ `Galaxy` có thể thành `spiral galaxy deep space NASA photograph`.

Khi thành công, app URL-encode query bằng `URLComponents` rồi mở `https://www.google.com/search?tbm=isch&q=...`. Khi lỗi, response rỗng hoặc timeout, app mở cùng URL bằng source text và hiện status ngắn. Nút bị vô hiệu khi source rỗng hoặc translation request đang chạy.

## Speech rate

Một pop-up button cạnh trái nút speech hiển thị 0.5x đến 1.5x. Giá trị dùng chung cho source và result, lưu trong UserDefaults, mặc định 1.0x.

Mỗi `AVAudioPlayer` bật `enableRate = true` và nhận `rate` trước `play()`. Thay đổi rate cập nhật player đang chạy nếu có. Audio trong History giữ 1.0x vì yêu cầu chỉ áp dụng popup Translate.

## Swap

Trước khi đổi selection, lấy cặp ngôn ngữ resolve từ text source hiện tại. Nếu source là Auto detect, source thực dùng `LanguageDetector.detectedLanguage(sourceText)`.

Sau đó:

- Đổi source text và result text.
- Source mới là target cũ.
- Target mới là source thực cũ.
- Invalidates current record/request/speech rồi cập nhật nhãn và layout.

Ví dụ Auto detect English sang Vietnamese trở thành Vietnamese sang English, tránh Vietnamese sang Vietnamese.

## Xử lý lỗi và an toàn dữ liệu

- Mọi thay đổi History persist JSON atomically trước khi cập nhật state trong memory.
- Chỉ xóa audio sau khi persist thành công; lỗi dọn audio không làm mất record metadata.
- Xóa hàng loạt luôn yêu cầu xác nhận và mô tả số record.
- Lỗi save/delete/image query hiện trong status hoặc sheet hiện có.
- Không thay đổi hoặc migrate schema JSON.

## Kiểm thử và tiêu chí hoàn thành

- Store tests: xóa một record, xóa tập record, record không tồn tại, audio liên quan được dọn.
- Filter tests: Today, 24h, Week, Month; kết hợp Saved Words và query.
- Language tests: swap Auto English→Vietnamese thành Vietnamese→English; text đổi hai chiều.
- Policy tests: kết quả hợp lệ không có record vẫn save được; Learn không làm mất điều kiện save.
- Translator test: image query request và fallback URL encoding ở logic thuần phù hợp.
- Chạy toàn bộ test suite.
- Chạy `./install-app.sh`, xác nhận build/sign/install thành công và báo version vừa build.
