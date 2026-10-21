# Log thông báo

Ứng dụng Flutter lưu thông báo Android vào SQLite. Logic ứng dụng nằm trong `lib/notifications/`:

| File Dart | Trách nhiệm |
| --- | --- |
| `balance_classifier.dart` | Nhận diện biến động số dư, chuẩn hóa tiếng Việt, điều kiện bao gồm/loại trừ |
| `notification_payload.dart` | Chọn tiêu đề, nội dung dự phòng, ghép tin nhắn và tên người gửi |
| `notification_store.dart` | Schema, migration SQLite, tìm kiếm, phân trang, chống trùng, lưu phân tích |
| `notification_worker.dart` | Xử lý nền, cấu hình, phân loại lại, hàng đợi phân tích và chống gọi API lặp |
| `gemini_analyzer.dart` | HTTP Gemini, prompt, schema JSON, kiểm tra phản hồi và thông báo lỗi |

`lib/notification_log_api.dart` là API cho giao diện. Các yêu cầu nghiệp vụ đi qua cầu nối tới cùng một Dart worker, nên mở/đóng Activity không tạo thêm hàng đợi phân tích. Entry point `notificationWorkerMain` trong `lib/main.dart` được giữ lại khi build release bằng `@pragma('vm:entry-point')`.

## Phần Android còn lại

Kotlin chỉ làm cầu nối nền tảng: `NotificationListenerService`, quyền và cài đặt hệ thống, đọc `Notification`/`Bundle`, hiển thị thông báo, Android Keystore, khởi động Flutter engine nền và thực thi SQLite theo câu lệnh Dart gửi xuống. Không còn bộ lọc hay HTTP Gemini trong Kotlin.

`NotificationDb.kt` có một bảng hàng đợi `native_inbox` để lưu ngay payload khi Dart chưa sẵn sàng hoặc thiết bị chưa mở khóa. Dart chuyển payload vào lịch sử và xóa khỏi hàng đợi trong cùng transaction. Database `notification_log.db`, phiên bản 3, vị trí device-protected storage, SharedPreferences và alias Keystore cũ đều được giữ nguyên. Migration từ phiên bản 1/2 chạy trong Dart.

Dart worker dùng một Flutter engine riêng, sống cùng tiến trình dịch vụ và tốn thêm bộ nhớ. Khi Android dừng tiến trình, dữ liệu đã lưu trong hàng đợi được xử lý lại ở lần dịch vụ/giao diện khởi động tiếp theo. Force-stop ứng dụng vẫn chịu giới hạn của Android.

## Bộ lọc và Gemini

Mở menu ☰ → **Chỉnh sửa bộ lọc thông báo**. Mỗi dòng là một cụm từ; không phân biệt hoa/thường hoặc dấu tiếng Việt. Điều kiện bao gồm yêu cầu ít nhất một dòng khớp; bất kỳ dòng loại trừ nào khớp đều loại thông báo. Để trống để dùng nhận diện tự động. Bộ lọc chạy trên máy, không cần API key.

Gemini chỉ được gọi khi mở chi tiết biến động số dư chưa phân tích hoặc bấm **Phân tích**. API key được mã hóa bằng Android Keystore. Nội dung thông báo được gửi tới Gemini khi phân tích và có thể phát sinh phí. Model có thể thay đổi trong cấu hình.

Kết quả hoặc lỗi được lưu, không tự gọi lại sau khi mở lại hoặc khởi động lại tiến trình. Bấm **Phân tích** để chủ động gọi lại. Đổi cụm từ sẽ phân loại lại trên máy, giữ nguyên phân tích cũ. HTTP chạy riêng để không chặn ghi nhận thông báo và xem lịch sử.

## Kiểm tra

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Test host cần Python 3 để kiểm thử repository bằng SQLite thật (thư viện chuẩn `sqlite3`), không cần package Python bên ngoài. Python không nằm trong ứng dụng.

Kiểm tra trên thiết bị: nhận thông báo khi mở và đóng giao diện; khởi động lại máy rồi mở khóa; nâng cấp từ bản cũ để kiểm tra lịch sử và key; đổi bộ lọc; phân tích lại với API key thật; thử mất mạng. Các test host không thay thế kiểm thử vòng đời Android và API thật.
