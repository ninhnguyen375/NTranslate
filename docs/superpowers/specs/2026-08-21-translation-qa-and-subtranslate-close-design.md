# Thiết Kế: Tính Năng Hỏi Đáp Về Bản Dịch (Q&A) & Nút Đóng Subtranslate

## Mục tiêu
1. Cho phép người dùng đặt câu hỏi phụ cho LLM dựa trên văn bản gốc và bản dịch hiện tại ngay trong popover.
2. Hiển thị câu trả lời inline bên dưới main pane trong một khung riêng biệt.
3. Thêm nút Đóng (icon `xmark` / `times`) cho khung subtranslate để người dùng có thể chủ động ẩn pane phụ.

---

## 1. Kiến trúc & Logic Backend (`Translator.swift`)

### Request Mode Mới
Thêm case vào `RequestMode`:
```swift
case ask(question: String, sourceText: String, translatedText: String, sourceLang: String, targetLang: String)
```

### System Prompt & Prompt Template
```markdown
You are an expert language assistant analyzing a translation.
<source-text>
{{sourceText}}
</source-text>

<translation>
{{translatedText}}
</translation>

Source language: {{sourceLang}}
Target language: {{targetLang}}

Answer the following user question concisely and directly in Vietnamese (or the user's requested language):
{{question}}
```

---

## 2. Giao diện Người Dùng (UI/UX)

### A. Ô Nhập Câu Hỏi (Q&A Input Bar)
- Vị trí: Đặt ở khu vực điều khiển hoặc thanh footer/body trong Popover.
- Thuộc tính:
  - Text field tùy chỉnh với placeholder `"Hỏi đáp thêm về bản dịch"`.
  - Hỗ trợ nhấn `Enter` để gửi câu hỏi.
  - Vô hiệu hóa khi chưa có nội dung dịch hoặc khi đang gửi request.

### B. Khung Hiển Thị Q&A (`QAPaneSection`)
- Cấu trúc: Tương tự `SubtranslateSection` nhưng là dạng single-card rộng toàn chiều ngang.
- Header Bar:
  - Title: `"Hỏi đáp / Q&A"`.
  - Icon buttons: Nút Copy nội dung câu trả lời, nút Đóng (`xmark`) để ẩn khung Q&A.
- Content:
  - `NSTextView` cuộn được, hiển thị phản hồi từ LLM.

### C. Nút Đóng cho Subtranslate (`SubtranslateSection`)
- Thêm `closeButton` (icon `xmark`) vào `resultHeaderBar` của `SubtranslateSection`.
- Action: Bấm nút sẽ gỡ bỏ `subSection`, kích hoạt tính toán lại layout thông qua `layoutSplitPrism` để đưa popover về kích thước pane đơn.

---

## 3. Quản Lý Kích Thước & Layout (`PopoverLayoutMath.swift` & `PopoverController+Chrome.swift`)

- Tính toán chiều cao linh hoạt cho các pane xếp chồng:
  - Main Pane
  - Subtranslate Pane (nếu mở)
  - QA Pane (nếu mở)
- `PopoverLayoutMath` hỗ trợ chia đều chiều cao khả dụng khi có nhiều section phụ đồng thời.

---

## 4. Xử Lý Lỗi & Các Trường Hợp Biên (Edge Cases)

- **Chuỗi rỗng**: Bỏ qua khi người dùng gửi khoảng trắng hoặc câu hỏi rỗng.
- **Lỗi mạng/API**: Hiển thị thông báo lỗi trực tiếp trong QA view hoặc thanh `statusLabel`.
- **Dịch văn bản mới**: Tự động reset và ẩn Q&A pane khi người dùng bắt đầu dịch một đoạn văn mới.
