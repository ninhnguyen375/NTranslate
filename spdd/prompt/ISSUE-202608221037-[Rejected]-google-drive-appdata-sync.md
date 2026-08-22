# ISSUE-202608221037 — [Feat] Google Drive appDataFolder sync

Sync `config.json` + `history.json` qua Google Drive appDataFolder. Mỗi user đăng
nhập Google account cá nhân, data nằm trong Drive của chính họ. Không backend,
không database, không chi phí vận hành.

---

## 1. Quyết định kiến trúc

| Vấn đề | Chọn | Lý do |
| --- | --- | --- |
| Nơi lưu | Drive `appDataFolder` | Ẩn với user, riêng theo app, không tính vào Drive UI. Ta không giữ data của ai. |
| Scope | `drive.appdata` | **Non-sensitive**. Publish chỉ cần brand verification, không cần video demo / security assessment. |
| OAuth client | Desktop app | macOS native. Loopback redirect vẫn được Google hỗ trợ cho Desktop (đã deprecate cho iOS/Android/Chrome, không phải desktop). |
| Redirect | `http://127.0.0.1:<random port>` | RFC 8252 §8.3: dùng IP literal, KHÔNG dùng `localhost` (tránh lỡ nghe trên interface ngoài). |
| PKCE | Bắt buộc | S256. |
| Token store | Keychain | Cạnh `APIKeyStore`, service `local.ninh.ntranslate`, account `googleRefreshToken`. |
| Conflict | Last-writer-wins + so `modifiedTime` | Một user nhiều máy, hiếm khi mở song song. |
| Sync trigger | Nền theo chu kỳ + nút thủ công | Local-first: app không bao giờ chờ mạng. |

**Loại bỏ:** Turso (không có auth), Supabase (ta thành người giữ data nhạy cảm của
user), CloudKit ($99/năm + phải đổi signing identity), git + launchd (user thường
không dựng được).

---

## 2. Việc phải làm trên Google Cloud Console (user tự thao tác)

Không tự động hoá được, không có Playwright MCP trong session này.

### 2.1 Tạo project + bật API

1. https://console.cloud.google.com/projectcreate — tên `NTranslate`.
2. APIs & Services → Library → tìm **Google Drive API** → Enable.

### 2.2 Branding (OAuth consent screen)

APIs & Services → OAuth consent screen:

- User type: **External**
- App name: `NTranslate`
- User support email: email của bạn
- App logo: tùy chọn (có logo thì phải qua brand verification kỹ hơn, cân nhắc bỏ trống lúc đầu)
- App domain / Home page: **cần một domain bạn sở hữu**
- Privacy policy URL: phải cùng domain với home page
- Authorized domain: domain đó
- Developer contact: email của bạn

### 2.3 Scope

Data Access → Add or remove scopes → thêm đúng một dòng:

```
https://www.googleapis.com/auth/drive.appdata
```

Xác nhận Console xếp nó vào nhóm **Non-sensitive**. Nếu thấy nó nằm ở Sensitive
thì dừng lại báo, nghĩa là có gì đó chọn sai.

### 2.4 OAuth client

Clients → Create client → Application type: **Desktop app** → tên `NTranslate macOS`.

Lưu lại `client_id` và `client_secret`.

### 2.5 Publish (BẮT BUỘC)

Audience → **Publish app**.

Để ở Testing thì refresh token hết hạn sau 7 ngày và giới hạn 100 test user.
Không ship được. Publish rồi refresh token sống 180 ngày và tự gia hạn khi dùng.

Vì scope non-sensitive nên publish không cần video demo. Vẫn cần brand
verification: xác minh sở hữu domain qua Google Search Console bằng chính tài
khoản là Owner/Editor của Cloud project.

**Chưa có domain thì đây là blocker duy nhất của toàn bộ feature.** Cần biết
trước khi tôi viết code.

---

## 3. Xử lý client_secret trên repo public

Repo `ninhnguyen375/NTranslate` là PUBLIC. Google nói Desktop client secret
"obviously not treated as a secret" và PKCE mới là lớp bảo vệ thật, nên lộ nó
không cho phép ai chiếm tài khoản user. Rủi ro thật là người khác nhúng client_id
của bạn vào app của họ và tiêu quota OAuth.

Chọn một:

**A. Nhúng thẳng vào source** (Google khuyến nghị chính thức cho Desktop).
Đơn giản nhất. Chấp nhận rủi ro quota.

**B. Nhúng qua build-time injection.** `install-app.sh` đọc từ biến môi trường,
sinh file Swift không commit. Repo sạch, nhưng ai tải DMG vẫn trích được từ
binary. Chỉ chặn được người lười.

**C. Bắt user tự tạo OAuth client** và dán client_id/secret vào Settings.
Repo sạch tuyệt đối, quota của user. Nhưng user thường không làm nổi.

Khuyến nghị **A**, đúng như tài liệu Google. Chuyển sang B nếu quota bị lạm dụng.

---

## 4. Thiết kế code

### 4.1 File mới

```
Sources/translate/GoogleAuth.swift        (~120 dòng)
Sources/translate/DriveAppDataClient.swift (~90 dòng)
Sources/translate/SyncManager.swift        (~90 dòng)
Tests/translateTests/SyncTests.swift       (~60 dòng)
```

### 4.2 File sửa

| File | Sửa gì |
| --- | --- |
| `Sources/translate/SettingsWindowController.swift` | Thêm tab "Sync": nút Sign in / Sign out, email tài khoản, thời điểm sync gần nhất, nút "Sync now" |
| `Sources/translate/PopoverController+Menu.swift` | Gọi `SyncManager.shared.syncInBackground()` sau khi save settings |
| `NTranslate.app/Contents/Info.plist` | Không đổi (loopback không cần `CFBundleURLSchemes`) |
| `Package.swift` | Không đổi (`URLSession` + `Network` là đủ, zero dependency) |

### 4.3 GoogleAuth.swift

```
struct GoogleTokens { accessToken, refreshToken, expiresAt, email }

final class GoogleAuth {
  static let shared
  func signIn() async throws -> GoogleTokens   // loopback + PKCE
  func accessToken() async throws -> String    // tự refresh khi hết hạn
  func signOut() throws                        // xoá Keychain + revoke token
  var isSignedIn: Bool
}
```

Luồng `signIn()`:

1. Sinh `code_verifier` 43-128 ký tự random, `code_challenge = base64url(SHA256(verifier))`.
2. Sinh `state` random để chống CSRF.
3. Mở `NWListener` trên `127.0.0.1` port 0 (OS cấp port trống).
4. `NSWorkspace.shared.open()` URL auth với `access_type=offline`, `prompt=consent`
   (bắt buộc để chắc chắn nhận refresh_token).
5. Nhận GET callback, **kiểm tra `state` khớp**, lấy `code`, trả trang HTML
   "You can close this window", đóng listener ngay.
6. POST `oauth2.googleapis.com/token` với `client_id`, `client_secret`, `code`,
   `code_verifier`, `grant_type=authorization_code`, `redirect_uri`.
7. Lưu `refresh_token` vào Keychain. `access_token` giữ trong memory.

Scope xin: `drive.appdata` + `userinfo.email` (để hiện email trong Settings cho
user biết đang đăng nhập tài khoản nào).

**Bảo mật:** listener chỉ bind `127.0.0.1`, đóng ngay sau khi nhận response, không
đặt `SO_REUSEADDR`/`SO_REUSEPORT` (RFC 8252 §B.5). Bắt buộc so `state`, thiếu bước
này là lỗ CSRF thật.

### 4.4 DriveAppDataClient.swift

Chỉ ba endpoint, không cần SDK:

```
func find(name: String) async throws -> DriveFile?
  GET /drive/v3/files?spaces=appDataFolder&q=name='config.json'&fields=files(id,modifiedTime)

func upload(name: String, data: Data, fileId: String?) async throws -> DriveFile
  POST /upload/drive/v3/files?uploadType=multipart   (tạo mới, parents:[appDataFolder])
  PATCH /upload/drive/v3/files/{id}?uploadType=media (ghi đè)

func download(fileId: String) async throws -> Data
  GET /drive/v3/files/{id}?alt=media
```

### 4.5 SyncManager.swift

```
final class SyncManager {
  static let shared
  func syncInBackground()          // fire-and-forget, nuốt lỗi mạng, ghi log
  func syncNow() async throws      // nút bấm, ném lỗi để UI hiện
  var lastSyncDate: Date?
  var lastError: String?
}
```

Thuật toán mỗi file (`config.json`, `history.json`):

```
remote = find(name)
if remote == nil:                       upload local
else if remote.modifiedTime > localMtime:  download, ghi local atomic, reload
else if localMtime > lastSyncedMtime:      upload local
else:                                      không làm gì
```

`lastSyncedMtime` lưu `UserDefaults` để phân biệt "local mới hơn vì user vừa sửa"
với "local mới hơn vì vừa download về".

Lịch: sync khi app khởi động, khi save settings, và mỗi 5 phút qua `Timer`. Không
dùng launchd (app đang chạy sẵn dạng `LSUIElement`).

### 4.6 Điểm đặc biệt của config.json

`config.json` chứa `apiBaseURL: "http://localhost:20128/..."`. Sync nguyên si thì
máy nào cũng trỏ localhost, đúng nếu mọi máy đều chạy 9Router local, sai nếu có
máy trỏ server thật.

Bạn đã chốt sync cả hai file. Tôi sẽ sync full config nhưng thêm một checkbox
"Sync API endpoints" trong tab Sync, mặc định BẬT. Tắt thì `apiBaseURL` +
`apiSpeechURL` giữ local, phần còn lại vẫn sync.

`historyDirectory` thì luôn giữ local, không sync, vì đường dẫn khác nhau giữa máy.

API key KHÔNG sync, vẫn nằm Keychain, user nhập tay mỗi máy.

Audio (`audio/`) KHÔNG sync ở bản này. Binary, phình nhanh, ít giá trị.

---

## 5. Kiểm chứng

`SyncTests.swift`, thuần logic, không gọi mạng:

1. `resolveAction()` trả `.upload` khi remote nil.
2. Trả `.download` khi remote mới hơn local.
3. Trả `.upload` khi local mới hơn `lastSyncedMtime`.
4. Trả `.noop` khi hai bên bằng nhau.
5. PKCE: `code_challenge` khớp `base64url(SHA256(verifier))` với vector cố định.
6. `state` không khớp thì `signIn()` ném lỗi.

Test 6 là quan trọng nhất, nó bảo vệ lớp chống CSRF.

Verify build bằng `swift build`. Không chạy `swift test` (toolchain thiếu module
`Testing`, theo CLAUDE.md), nên test viết dạng assert chạy được qua một entry
`demo()` gọi tay.

Kiểm thử thủ công cuối:

1. Sign in trên máy A, sửa một prompt, bấm Sync now.
2. Sign in cùng tài khoản trên máy B, bấm Sync now, xác nhận prompt về đúng.
3. Rút mạng, dịch vài câu, cắm lại, xác nhận history đẩy lên không mất.
4. Sign out, xác nhận Keychain sạch và token bị revoke.

---

## 6. Thứ tự thi công

1. `GoogleAuth.swift` + test PKCE/state → `swift build`
2. `DriveAppDataClient.swift` → gọi thật một lần, xác nhận file hiện trong appDataFolder
3. `SyncManager.swift` + test resolveAction
4. Tab Sync trong Settings
5. Nối vào save settings + timer 5 phút
6. `./install-app.sh`, kiểm thử thủ công hai máy

---

## 7. Cần bạn trả lời trước khi bắt đầu

1. **Có domain riêng không?** Cần để host privacy policy và xác minh với Google.
   Không có thì không publish được, refresh token chết sau 7 ngày, feature vô dụng.
2. **client_secret theo phương án A, B hay C?** (mục 3)
3. **Đã tạo Google Cloud project chưa,** hay bạn làm theo mục 2 rồi đưa tôi
   `client_id` + `client_secret`?

Câu 1 là chặn cứng. Hai câu còn lại chỉ đổi chi tiết.
