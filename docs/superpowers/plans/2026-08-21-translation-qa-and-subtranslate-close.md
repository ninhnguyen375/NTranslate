# Kế Hoạch Triển Khai: Translation Q&A & Nút Đóng Subtranslate

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm tính năng hỏi đáp về bản dịch (Q&A) kèm ô input và khung hiển thị câu trả lời inline bên dưới popover; thêm nút đóng khung subtranslate.

**Architecture:** Bổ sung `RequestMode.ask` và phương thức gọi LLM trong `Translator.swift`. Xây dựng `QAPaneSection` và trường nhập liệu trong `PopoverController`, đồng thời tính toán layout xếp chồng trong `PopoverController+Chrome.swift` và `PopoverLayoutMath.swift`. Bổ sung nút close vào `SubtranslateSection`.

**Tech Stack:** Swift, AppKit, macOS native APIs.

## Global Constraints
- Tuân thủ hướng dẫn kiểm tra qua `swift build` (không dùng `swift test`).
- Giữ nguyên thiết kế Liquid Glass / Prism styling.
- Đảm bảo layout co giãn mượt mà, không tràn cửa sổ.

---

### Task 1: Thêm Nút Đóng Cho Subtranslate (`SubtranslateSection`)

**Files:**
- Modify: `Sources/translate/SubtranslateSection.swift`
- Modify: `Sources/translate/PopoverController+Subtranslate.swift`
- Modify: `Sources/translate/PopoverController+Chrome.swift`

- [ ] **Step 1: Thêm thuộc tính `closeButton` vào `SubtranslateSection`**
Thêm `let closeButton = NSButton(frame: .zero)` vào `SubtranslateSection`.

- [ ] **Step 2: Cấu hình `closeButton` trong `PopoverController+Subtranslate.swift`**
Thêm action đóng: gọi selector `@objc func closeSubtranslate()` để gỡ bỏ `subSection` và gọi `updatePanelSize()`.

- [ ] **Step 3: Layout `closeButton` trong header của `SubtranslateSection`**
Cập nhật `trailingIcons` trong header để hiển thị nút `xmark`.

- [ ] **Step 4: Kiểm tra build**
Chạy: `swift build`
Expected: Build thành công.

- [ ] **Step 5: Commit**
`git commit -am "feat: add close button to subtranslate pane"`

---

### Task 2: Cập Nhật `Translator.swift` Hỗ Trợ Chế Độ Q&A

**Files:**
- Modify: `Sources/translate/Translator.swift`

- [ ] **Step 1: Thêm mode `ask` vào `RequestMode`**
Thêm case `ask(question: String, sourceText: String, translatedText: String, sourceLang: String, targetLang: String)`.

- [ ] **Step 2: Xây dựng Prompt Generator cho Q&A**
Tạo hàm `renderQAPrompt(question: String, sourceText: String, translatedText: String, sourceLang: String, targetLang: String) -> String`.

- [ ] **Step 3: Thêm method `ask(...)` vào `Translator`**
Tạo hàm công khai `ask(_ question: String, sourceText: String, translatedText: String, sourceLang: String, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void)`.

- [ ] **Step 4: Kiểm tra build**
Chạy: `swift build`
Expected: Build thành công.

- [ ] **Step 5: Commit**
`git commit -am "feat: add ask request mode and prompt to Translator"`

---

### Task 3: Tạo `QAPaneSection` & Ô Nhập Liệu Q&A

**Files:**
- Create: `Sources/translate/QAPaneSection.swift`
- Modify: `Sources/translate/PopoverController.swift`
- Create: `Sources/translate/PopoverController+QA.swift`

- [ ] **Step 1: Tạo lớp `QAPaneSection`**
Bao gồm `card`, `headerBar`, `headerLabel`, `copyButton`, `closeButton`, `scrollView`, `textView`.

- [ ] **Step 2: Thêm `qaInputField` vào `PopoverController`**
Tạo `NSTextField` với placeholder `"Hỏi đáp thêm về bản dịch"`, xử lý sự kiện nhấn Enter.

- [ ] **Step 3: Tạo file `PopoverController+QA.swift` quản lý logic Q&A**
Triển khai `sendQAQuestion()`, `makeQASection()`, `closeQASection()`.

- [ ] **Step 4: Kiểm tra build**
Chạy: `swift build`
Expected: Build thành công.

- [ ] **Step 5: Commit**
`git commit -am "feat: add QAPaneSection and QA input bar"`

---

### Task 4: Tích Hợp Layout Xếp Chồng Q&A Vào Chrome

**Files:**
- Modify: `Sources/translate/PopoverLayoutMath.swift`
- Modify: `Sources/translate/PopoverController+Chrome.swift`

- [ ] **Step 1: Cập nhật hàm tính chiều cao layout trong `PopoverLayoutMath.swift`**
Mở rộng hỗ trợ tính toán chiều cao khi có thêm QA pane.

- [ ] **Step 2: Tích hợp layout QA pane và input field trong `PopoverController+Chrome.swift`**
Điều chỉnh vị trí các nút bottom bar và vị trí của QA pane khi hiển thị.

- [ ] **Step 3: Kiểm tra build**
Chạy: `swift build`
Expected: Build thành công.

- [ ] **Step 4: Commit**
`git commit -am "feat: integrate QA pane layout into PopoverController chrome"`

---

### Task 5: Xác Thực & Hoàn Thiện

**Files:**
- Build & Manual verification

- [ ] **Step 1: Build toàn bộ ứng dụng**
Chạy: `swift build`

- [ ] **Step 2: Cài đặt và kiểm tra thử ứng dụng**
Chạy: `./install-app.sh`

- [ ] **Step 3: Commit cuối cùng nếu có sửa đổi**
