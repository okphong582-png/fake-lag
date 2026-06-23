# FakeLag iOS 🎮

**Giả lập nghẽn mạng nhẹ trên iOS** — Nhấn START, app tự động:
1. Chuyển sang app khác
2. Sau **2 giây** → kích hoạt fake lag (~800ms delay mỗi request)
3. Sau **2 giây** tiếp → tự động tắt lag

---

## 📦 Download IPA

Xem tại [**Releases**](../../releases) — tải file `FakeLag-unsigned.ipa`

## 📱 Cài đặt

| Phương pháp | Yêu cầu |
|---|---|
| **TrollStore** | iOS 14-16.x (tùy device) |
| **AltStore** | Bất kỳ iOS, cần re-sign mỗi 7 ngày |
| **Xcode** (dev) | Mac + free Apple ID |

## 🛠️ Build từ source

```bash
git clone https://github.com/okphong582-png/fake-lag.git
cd fake-lag/FakeLag
open FakeLag.xcodeproj
```

Mở trong Xcode → chọn device → Build & Run.

## ✨ Tính năng

- 🔵 Nút START to ở giữa màn hình
- 📏 Slider chỉnh kích cỡ nút (80–280pt)
- ⚡ Fake lag tự động bật/tắt (2s + 2s)
- 🌑 Giao diện dark mode premium
- 💫 Animation glowing + pulse

## ⚠️ Lưu ý

IPA này **unsigned** — chỉ cài được qua TrollStore hoặc AltStore (không qua App Store chính thức).

Fake lag hoạt động bằng cách chặn URLSession requests và thêm delay nhân tạo.
