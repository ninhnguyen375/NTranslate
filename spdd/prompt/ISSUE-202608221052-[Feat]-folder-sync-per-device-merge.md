# ISSUE-202608221052 — [Feat] Per-device monthly files, merge by record id

Đổi bố cục lưu lịch sử: mỗi máy ghi file riêng, tách theo tháng. Nhờ đó user trỏ
`historyDirectory` vào bất kỳ thư mục sync nào (iCloud Drive, Dropbox, Google
Drive, OneDrive, Syncthing, ổ mạng) là nhiều máy dùng chung được ngay, không
conflict.

Không thêm setting mới. Không OAuth, không backend, không dependency, không code
mạng. Hạ tầng sync là của user, do user chọn.

---

## 1. Nguyên tắc

**Mỗi máy chỉ ghi file của riêng nó, mỗi tháng một file.**

```
<historyDirectory>/
  devices/
    macbook-a1b2c3/
      2026-08.json      ← chỉ máy này ghi, và chỉ file tháng này bị ghi lại
      2026-07.json      ← bất biến, dịch vụ sync không đụng tới
    imac-d4e5f6/
      2026-08.json
  audio/
    <record-uuid>-source.mp3
```

Hai tính chất, mỗi cái giải một vấn đề khác nhau:

**Per-device** giải conflict. Không máy nào ghi đè file của máy khác nên Dropbox
và iCloud không bao giờ sinh ra `history 2.json`. Merge thành phép hợp theo `id`.

**Per-month** giải chi phí ghi **và RAM**. Hiện `persist()` ghi lại toàn bộ file
mỗi lần `append()`. Đo thực tế trên máy này ở mức 90k record (~5 năm dùng nặng):

| | 1 file | 60 file tháng |
| --- | --- | --- |
| Peak RSS lúc load | 175 MB | **48 MB** |
| Ghi mỗi lần append | 44 MB | ~750 KB |
| Encode mỗi lần append | 350ms | ~6ms |

Đọc một file lớn thì `Data` 44 MB, mảng object, và bộ đệm `JSONDecoder` cùng tồn
tại một lúc. Đọc từng file trong `autoreleasepool` thì mỗi vòng chỉ giữ ~750 KB.

Tách theo tháng thắng cả ba mặt.

Giữ **toàn bộ** lịch sử, không giới hạn số record, không tự xoá gì.

### Vì sao không cần setting `syncDirectory` riêng

Thư mục Dropbox và iCloud Drive là thư mục local. Ghi vào đó nhanh như ghi
Application Support, dịch vụ tự đẩy đi nền. Bố cục per-device hoạt động ở bất kỳ
đâu, nên chỉ cần user trỏ `historyDirectory` (đã có sẵn) vào thư mục sync.

Bỏ được: setting thứ hai, bước copy hai chiều, sync audio riêng, kiểm tra trùng
đường dẫn giữa hai thư mục.

---

## 2. Merge

`TranslationRecord` đã có `id: UUID` và `timestamp: Date`. Thêm hai field:

```swift
var updatedAt: Date    // decode bản cũ → = timestamp
var deletedAt: Date?   // tombstone
```

`updatedAt` cần vì `isSaved`, `dueDate`, `interval`, `ease` đổi được sau khi tạo.
`timestamp` là lúc dịch, không phải lúc sửa. Thiếu nó thì máy A bấm sao chưa chắc
thắng máy B.

Luật merge:

```
gom mọi record từ devices/*/*.json
nhóm theo id
mỗi nhóm lấy bản có updatedAt lớn nhất
bằng nhau thì lấy bản có deviceID sắp xếp nhỏ hơn (mọi máy ra cùng kết quả)
```

Hợp theo id là merge **đúng** cho dữ liệu chỉ thêm vào, không phải thoả hiệp. Hai
máy dịch hai câu khác nhau thì giữ được cả hai, khác hẳn last-writer-wins.

**Xoá phải dùng tombstone.** Xoá thật thì record sống lại từ file máy khác ở lần
đọc kế. Record xoá được đánh `deletedAt`, merge coi nó như một bản cập nhật bình
thường. Giữ tombstone **1 năm** rồi mới dọn (không phải 90 ngày: máy lâu không mở
rồi bật lại sẽ hồi sinh record đã xoá).

Đây là chỗ dễ sai nhất của feature, có test riêng và bước kiểm thử thủ công riêng.

---

## 3. Đọc và ghi

**Ghi** (`persist`): chỉ ghi `devices/<myID>/<tháng của record>.json`, atomic. Một
lần append chạm đúng một file. Record cũ sửa (bấm sao, cập nhật SRS) thì ghi vào
file tháng gốc của record đó, không phải tháng hiện tại.

**Đọc** (`load`): quét mọi `devices/*/*.json`, decode **từng file trong
`autoreleasepool`**, merge, sắp xếp. Chỉ chạy lúc khởi động và khi refresh.

`autoreleasepool` mỗi file là bắt buộc, không phải tối ưu vặt: thiếu nó thì mọi
`Data` trung gian sống tới hết vòng lặp và peak RSS quay về mức của bản một file.

Toàn bộ `records` giữ trong RAM sau khi load (~48 MB ở 90k record). Xem mục 14
nếu cần giảm tiếp.

**Refresh**: `Timer` mỗi 2 phút gọi lại `load()` để nhận thay đổi từ máy khác.
Không dùng `FSEventStream` ở bản này.

**Ghi atomic bắt buộc** (`.atomic`, như `persist()` đang làm). Dropbox đọc file
đang ghi dở sẽ đẩy bản JSON hỏng cho mọi máy.

---

## 4. File bị đẩy lên mây (quan trọng)

iCloud Drive bật "Optimize Mac Storage" sẽ đẩy file ít dùng lên mây, để lại
placeholder rỗng trên đĩa. Dropbox Smart Sync và OneDrive Files On-Demand cũng
vậy. **File tháng cũ đúng là loại bị nhắm tới.**

Xử lý:

1. Đọc lỗi hoặc `NSURLUbiquitousItemDownloadingStatusKey` khác `.current` thì gọi
   `FileManager.startDownloadingUbiquitousItem(at:)`, bỏ qua file đó ở lần này,
   thử lại ở lần refresh sau.
2. **Tuyệt đối không coi file không đọc được là dữ liệu đã mất.** Không ghi đè,
   không xoá, không sinh lại. Đây là đường ngắn nhất để mất lịch sử thật của user.
3. Ghi vào `loadError` để UI cho user biết đang thiếu dữ liệu tạm thời.

---

## 5. Config

`config.json` không có id per-record nên không merge theo cách trên. Mỗi máy ghi
`devices/<myID>/config.json`, đọc thì lấy file `mtime` mới nhất trong các máy.
Last-writer-wins, chấp nhận được vì user hiếm khi sửa settings hai máy cùng lúc.

Ba field **không bao giờ sync** vì phụ thuộc máy:

- `apiBaseURL`, `apiSpeechURL` — máy này chạy 9Router local, máy kia có thể trỏ server
- `historyDirectory` — chính nó, đường dẫn khác nhau giữa máy

Lọc ra trước khi ghi, đọc thì giữ giá trị local. Checkbox "Sync API endpoints" cho
user bật nếu mọi máy giống nhau, mặc định **TẮT** (bật nhầm là app trỏ sai server
và ngừng dịch được).

API key vẫn ở Keychain, không sync, nhập tay mỗi máy.

---

## 6. Device ID

```swift
// UserDefaults key "syncDeviceID", sinh một lần
let id = "\(Host.current().localizedName ?? "mac")-\(UUID().uuidString.prefix(6))"
```

Có tên máy để user mở thư mục là biết file nào của máy nào. Hậu tố random để hai
máy trùng tên không đụng nhau.

---

## 7. Audio

Nằm sẵn trong `historyDirectory` nên tự đi theo, không cần code copy.

Tên file theo `record-uuid` nên không đụng nhau giữa các máy.

**Dọn file mồ côi**: hiện không có cơ chế nào, file audio ở lại cả khi record bị
xoá. Đây mới là thứ thật sự phình vì là binary. Lúc `load()`, xoá file audio không
còn record nào tham chiếu (bỏ qua record trong tombstone chưa hết hạn).

---

## 8. Migration

User hiện có `history.json` một file. Lần chạy đầu sau khi lên bản mới:

```
nếu tồn tại history.json và devices/ chưa có:
    đọc history.json
    chia record theo tháng của timestamp
    ghi devices/<myID>/<tháng>.json
    đổi tên history.json → history.json.migrated  (KHÔNG xoá)
```

Giữ file cũ để user còn đường lùi. Xoá tay sau khi yên tâm.

Decode record cũ thiếu `updatedAt` thì gán `= timestamp`, thiếu `deletedAt` thì
`nil`. Có test riêng cho bước này vì nó đụng dữ liệu người đang dùng.

---

## 9. Code

### 9.1 File sửa

| File | Sửa gì |
| --- | --- |
| `TranslationHistoryStore.swift` | Phần lớn công việc. `updatedAt` + `deletedAt` trong `TranslationRecord`; `persist()` ghi theo tháng; `load()` quét + merge; `merge()`; migration; dọn audio mồ côi; dọn tombstone |
| `AppConfig.swift` | Thêm `syncAPIEndpoints: Bool` (mặc định false) |
| `SettingsWindowController.swift` | Tab Advanced: sửa nhãn `historyDirectoryField` thành "History folder (point at a synced folder to share across Macs)"; thêm checkbox "Sync API endpoints"; nhãn hiện số máy đang thấy |
| `PopoverController.swift` | `Timer` 2 phút gọi refresh |

Không thêm file mới. Không đụng `Package.swift`.

### 9.2 API mới trong store

```swift
func merge(_ groups: [[TranslationRecord]]) -> [TranslationRecord]
func refresh()                    // đọc lại từ đĩa, nhận thay đổi máy khác
private func monthKey(_ date: Date) -> String   // "2026-08", UTC
private func pruneOrphanAudio()
private func pruneTombstones()
```

`monthKey` dùng **UTC**, không dùng múi giờ máy. Hai máy khác múi giờ mà chia
tháng khác nhau thì cùng một record rơi vào hai file khác nhau, merge vẫn đúng
nhưng file phình vô ích.

---

## 10. Rủi ro đã lường

**File hỏng ở một máy.** Decode lỗi thì bỏ qua file đó, ghi `loadError`, các file
khác vẫn merge. Một máy hỏng không kéo sập cả hệ thống.

**Thư mục sync biến mất** (rút ổ ngoài, huỷ liên kết Dropbox). `load()` ném lỗi,
app không được xoá hay reset gì. Hiện `ensureWritable()` đã chặn ghi khi có
`loadError`, giữ nguyên hành vi đó.

**Hai máy ghi cùng lúc.** Mỗi máy một file nên không đụng. Xấu nhất là A đọc file
B đúng lúc B đang ghi, nhưng ghi atomic nên A thấy bản cũ nguyên vẹn.

**Dữ liệu nhạy cảm.** Lịch sử dịch có thể chứa email, hợp đồng, thông tin riêng.
Đặt `0o700` cho thư mục, `0o600` cho file, như `migrateLegacyAPIKey` đang làm. User
để thư mục trong Dropbox chia sẻ chung là quyết định của họ, nhưng app không tự
nới quyền.

**Số máy tăng dần.** Mỗi máy cũ để lại một thư mục `devices/<id>/` vĩnh viễn. Máy
bán đi rồi vẫn còn dữ liệu, đúng ý muốn (không mất lịch sử), nhưng nên có nút
"Forget device" trong Settings. Để bản sau, không chặn.

---

## 11. Kiểm chứng

`FolderSyncTests.swift`, thuần logic, chạy trên thư mục tạm:

1. Merge hai danh sách rời nhau → hợp đủ cả hai
2. Cùng `id`, `updatedAt` khác nhau → bản mới thắng
3. Cùng `id`, `updatedAt` bằng nhau → kết quả giống nhau bất kể thứ tự đầu vào
4. Record có `deletedAt` không sống lại từ file máy khác
5. Tombstone quá 1 năm bị dọn
6. File JSON hỏng bị bỏ qua, file khác vẫn merge
7. Decode record bản cũ (không `updatedAt`) → `updatedAt = timestamp`
8. Migration `history.json` → nhiều file tháng, không mất record nào, file gốc còn nguyên
9. `append()` chỉ chạm đúng một file tháng
10. Sửa record cũ ghi vào file tháng gốc, không phải tháng hiện tại
11. Audio mồ côi bị dọn, audio của record trong tombstone thì không

Quan trọng nhất: **4** (ngữ nghĩa xoá), **7** và **8** (dữ liệu người đang dùng),
**10** (dễ viết sai nhất).

Verify build `swift build`. Không chạy `swift test` (toolchain thiếu module
`Testing`, theo CLAUDE.md). Test viết dạng assert gọi qua `demo()` chạy tay.

Kiểm thử thủ công:

1. Máy A trỏ history vào `~/Library/Mobile Documents/com~apple~CloudDocs/NTranslate`, dịch 3 câu
2. Máy B trỏ cùng thư mục, chờ sync, mở app, thấy đủ 3 câu
3. Máy B dịch thêm 2 câu, cả hai máy thấy đủ 5
4. Máy A bấm sao một record, máy B thấy đã sao
5. Máy A xoá một record, máy B thấy mất và **không sống lại** sau lần refresh kế
6. Đổi sang `~/Dropbox/NTranslate`, xác nhận chạy y hệt
7. Bật "Optimize Mac Storage", để một tháng cũ bị đẩy lên mây, xác nhận app không
   báo mất dữ liệu và kéo file về được

Bước 5 và 7 dễ hỏng nhất, làm kỹ.

---

## 12. Thứ tự thi công

1. `updatedAt` + `deletedAt`, giữ tương thích decode bản cũ → test 7 → `swift build`
2. `merge()` → test 1-4
3. `persist()` theo tháng + `load()` quét thư mục → test 9, 10
4. Migration từ `history.json` → test 8
5. Xử lý file trên mây (mục 4) → test 6
6. Dọn tombstone + audio mồ côi → test 5, 11
7. UI: nhãn mới, checkbox, timer refresh
8. `./install-app.sh`, kiểm thử thủ công hai máy

Bước 1-4 là phần đụng dữ liệu người dùng, làm chậm và chắc.

---

## 13. Không làm ở bản này

- Giới hạn số record. Giữ toàn bộ lịch sử là quyết định đã chốt.
- `FSEventStream` theo dõi thư mục. Timer 2 phút đủ, thêm khi user thấy chậm.
- Nút "Forget device".
- Nén file. JSON thô đọc được bằng mắt, quý hơn vài MB.
- Mã hoá phía app. Dịch vụ sync của user đã có lớp của họ; thêm nữa thì mất khoá
  là mất data.
- Sync API key. Cố ý giữ trong Keychain từng máy.
- Lazy load theo tháng (mục 14). Chốt làm option A trước.

---

## 14. Đường nâng cấp RAM (chưa làm)

`load()` giữ toàn bộ `records` trong RAM: ~10 MB sau năm đầu (18k record), ~48 MB
ở năm thứ 5 (90k record). Với app menu bar chạy nền cả ngày thì 48 MB là con số
thật, nhưng còn xa mới thành vấn đề.

Khi chạm ngưỡng, nâng cấp bằng **lazy load 3 tháng gần nhất** (~3 MB thường trú),
tháng cũ đọc theo yêu cầu khi user cuộn trong History window. Khoảng 40 dòng.

Đánh đổi: `reusableRecord()` (cache tra bản dịch cũ) chỉ phủ 3 tháng, nên câu đã
dịch từ lâu sẽ gọi lại API. Hiếm, và không gây lỗi.

**Không đòi đổi định dạng file.** Bố cục per-device/per-month đã đủ để nâng cấp
sau, chỉ đổi cách đọc. Đó là lý do làm option A trước là an toàn.

Ghi `// ponytail:` tại `load()` nói rõ ngưỡng và đường nâng cấp này.
