## Workflow

- Luôn chạy `./install-app.sh` sau khi hoàn thành task (build + sign + install vào `/Applications/NTranslate.app`).
- Luôn báo user số version vừa build (in ra từ output install-app.sh) để user biết và test.

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

### Biến môi trường hữu ích

| Biến | Ý nghĩa |
| --- | --- |
| `VERSION_BUMP=patch\|minor\|major` | Truyền xuống `install-app.sh` (mặc định `patch`) |
| `SKIP_INSTALL=1` | Không build lại; dùng app đang có trong `/Applications` |
| `SKIP_UPLOAD=1` | Chỉ tạo DMG local, không gọi `gh release` |
| `DRAFT=1` | Tạo draft release trên GitHub |
| `NOTES_FILE=path.md` | Release notes tùy chỉnh |

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

Sau khi release xong: báo user URL release + version/build + tên file DMG. Nếu `README.md` đổi, commit + push thay đổi đó cùng (nếu user đang yêu cầu publish).
