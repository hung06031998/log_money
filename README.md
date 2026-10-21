# Nhật ký thông báo Android

Ứng dụng Flutter + Kotlin, Android 7.0 (API 24) trở lên. Nhận thông báo bằng `NotificationListenerService`, ghi SQLite trong native Android, xem lịch sử bằng Flutter. Không cần mở giao diện để lưu. Không gửi dữ liệu lên máy chủ; tắt Android backup cho dữ liệu ứng dụng.

## Cài và sử dụng

```sh
flutter pub get
flutter run
# Hoặc tạo APK cài thử:
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`. Đây là bản cài thử ký debug, chưa phải bản phát hành lên cửa hàng.

1. Mở ứng dụng, chọn **Quyền thông báo**, bật quyền truy cập cho **Nhật ký thông báo**. Android yêu cầu người dùng tự cấp quyền đọc dữ liệu này. Một số thiết bị chặn quyền của APK cài ngoài; kiểm tra phần “Cho phép cài đặt bị hạn chế” trong thông tin ứng dụng nếu có.
2. Kiểm tra dòng **Đang kết nối với Android**. Vào **Thiết lập** để mở cài đặt pin, đặt ứng dụng ở chế độ không hạn chế; bật tự khởi động nếu hãng máy có tùy chọn này.
3. Nhận thông báo mới, mở lịch sử; nhấn bản ghi để xem đầy đủ văn bản và JSON metadata. Có bản ghi mới thì nhấn nút xem mới hoặc làm mới. Lịch sử cũ giữ vị trí khi có sự kiện mới.
4. Dùng **Tải thêm thông báo** để đọc tiếp toàn bộ lịch sử, mỗi trang 50 bản ghi. Tìm kiếm trong ứng dụng, package, tiêu đề và nội dung; SQLite hỗ trợ tìm Unicode chính xác nhưng không có case folding đầy đủ cho mọi ký tự tiếng Việt.

## Phạm vi bảo đảm và giới hạn

Không có ứng dụng Android thông thường nào bảo đảm “không bỏ sót 100% trong mọi điều kiện”. Android/OEM có thể dừng tiến trình, người dùng thu hồi quyền, buộc dừng ứng dụng, hồ sơ công việc có chính sách hạn chế, thiết bị đầy bộ nhớ hoặc bị mất nguồn. Khi bị buộc dừng, cần mở lại ứng dụng. Sau reboot cần mở khóa để truy cập database.

- Mỗi `onNotificationPosted` được ghi thành một hàng riêng, gồm cả lần cập nhật cùng khóa, thông báo nhóm và thông báo ongoing. Không lọc theo ứng dụng và không tự xóa lịch sử.
- SQLite commit đồng bộ với `synchronous=FULL` trước khi callback hoàn tất; không đi qua Flutter, không dùng hàng đợi chỉ nằm trong RAM. Đánh đổi: tốc độ ghi phụ thuộc bộ nhớ thiết bị, cần thử tải lớn trên thiết bị đích. Vẫn có khoảng rủi ro nếu tiến trình bị giết trước khi commit hoặc storage lỗi; chưa có hàng đợi retry bền vững ngoài SQLite.
- Khi kết nối lại, lấy các thông báo còn hoạt động; chỉ bỏ bản khôi phục có cùng key/postTime/payload đã lưu. Không khôi phục được những thông báo đã biến mất trong thời gian mất kết nối, hoặc các phiên bản trung gian bị cập nhật khi mất kết nối.
- Yêu cầu rebind sau ngắt kết nối, reboot và cập nhật ứng dụng. Đây là yêu cầu tới hệ thống, không bảo đảm thời điểm Android sẽ kết nối lại. Không dùng foreground service để đưa ra bảo đảm giả rằng listener luôn được kết nối.
- Lưu tiêu đề, nội dung thường/mở rộng, text lines, tin nhắn hội thoại, thời gian, nguồn, package, key, channel, group, action labels và extras dạng JSON. Trường parcelable phi văn bản có dấu `[Non-text ...]`; trường không đọc được có dấu `[Unreadable ...]`. Không sao chép ảnh, tệp đính kèm, PendingIntent hay RemoteViews tùy biến.
- Android 15+ có thể che nội dung OTP. Chỉ lưu được những gì hệ thống chuyển cho listener; không vượt qua giới hạn này.
- Màn hình không giới hạn số trang hay rút gọn văn bản bản ghi. Phân trang theo ID, không dùng offset nên dữ liệu đến mới không làm nhảy/mất hàng cũ. Các trang đã xem được giữ trong RAM; lịch sử cực lớn có thể cần tối ưu cửa sổ giao diện trong phiên bản sau.
- Lỗi ghi/khôi phục gần nhất được lưu riêng trong preferences và hiển thị; không tự xóa dấu lỗi khi có sự kiện tiếp theo thành công. Hết dung lượng nghiêm trọng cũng có thể làm mất cả khả năng ghi dấu lỗi.
- Dữ liệu nằm trong sandbox ứng dụng, không có mã hóa riêng hoặc khóa sinh trắc học. Gỡ ứng dụng/xóa dữ liệu sẽ mất lịch sử.

Tài liệu nền tảng: [NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService), [Android 15 và nội dung nhạy cảm](https://developer.android.com/about/versions/15/behavior-changes-all).

## Kiểm thử

```sh
flutter analyze
flutter test
cd android
./gradlew :app:connectedDebugAndroidTest
```

Kiểm thử Flutter: trạng thái kết nối, phân trang trong khi nhận thêm dữ liệu, tìm kiếm không có kết quả, hiển thị lỗi database.

Kiểm thử instrumentation (cần thiết bị/máy ảo): callback trùng vẫn giữ, snapshot phục hồi không ghi trùng, phân trang đồng thời có ghi mới, lưu Unicode dài qua đóng/mở database. Dùng database `test-notifications.db` tách khỏi lịch sử thực.

Trước khi dùng lâu dài trên điện thoại thực, cần đối chiếu số bản ghi với nguồn phát: gửi một đợt thông báo đánh số, cập nhật lại cùng ID, thử màn hình tắt/Doze, vuốt đóng giao diện, khởi động lại, thu hồi/cấp lại quyền. Kiểm tra cả thông báo nhóm, MessagingStyle và nội dung dài. Kiểm thử database không chứng minh Android chuyển đủ mọi callback.
