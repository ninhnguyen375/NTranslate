# Tài liệu luồng hoạt động NTranslate macOS — Kế hoạch thực hiện

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tạo `docs/macos-app-flows.md` mô tả toàn bộ chức năng và nghiệp vụ người dùng của app macOS bằng tiếng Việt tự nhiên, kèm biểu đồ Mermaid.

**Architecture:** Một tài liệu duy nhất tổ chức theo hành trình người dùng. Nội dung được đối chiếu trực tiếp với source dưới `Sources/translate/`; dùng flowchart cho nhánh quyết định và sequence diagram cho phiên dịch chính.

**Tech Stack:** Markdown, Mermaid, Swift source làm nguồn đối chiếu.

## Global Constraints

- Chỉ mô tả app macOS.
- Không nêu class, hàm hoặc chi tiết triển khai Swift trong nội dung chính.
- Bao phủ đủ khởi động, menu bar, mở cửa sổ, lấy nội dung, dịch, ngôn ngữ, phát âm, sao chép, lịch sử, cài đặt, Accessibility, cập nhật và thoát.
- Chỉ ghi hành vi có bằng chứng trong source hiện tại.
- Không sửa source, không chạy installer, không commit.

---

### Task 1: Tạo tài liệu luồng hoạt động

**Files:**
- Create: `docs/macos-app-flows.md`
- Reference: `Sources/translate/*.swift`

**Interfaces:**
- Consumes: Hành vi người dùng thể hiện trong source macOS.
- Produces: Tài liệu Markdown độc lập, đọc được trên trình kết xuất hỗ trợ Mermaid.

- [ ] **Step 1: Đối chiếu các luồng người dùng trong source**

Xác nhận điểm bắt đầu, nhánh quyết định và kết quả của 13 nhóm chức năng trong đặc tả.

- [ ] **Step 2: Viết tài liệu tối thiểu nhưng đủ phạm vi**

Tạo `docs/macos-app-flows.md` gồm tổng quan, mục lục, luồng tổng, từng nhóm chức năng và các sơ đồ Mermaid nhỏ.

- [ ] **Step 3: Kiểm tra cấu trúc Markdown và phạm vi**

Run:

```powershell
$path = 'docs/macos-app-flows.md'
$text = Get-Content -Raw $path
if (-not (Test-Path $path)) { throw 'Missing docs/macos-app-flows.md' }
if (($text | Select-String -Pattern '```mermaid' -AllMatches).Matches.Count -lt 3) { throw 'Expected at least 3 Mermaid diagrams' }
if (($text | Select-String -Pattern '```' -AllMatches).Matches.Count % 2 -ne 0) { throw 'Unbalanced Markdown fences' }
```

Expected: exit code `0`, không có output lỗi.

- [ ] **Step 4: Kiểm tra diff tài liệu**

Run:

```powershell
git diff --check
git status --short
```

Expected: `git diff --check` không có lỗi; status chỉ có ba file tài liệu mới của tác vụ trong `docs/`.
