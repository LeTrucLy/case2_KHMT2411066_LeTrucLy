# TASK MANAGER — Case Study 2

Ứng dụng quản lý và giao công việc nhóm: **Flutter + Node.js/Express + MongoDB + Nodemailer**.

## Thông tin sinh viên

- Họ tên: Lê Trúc Ly
- MSSV: KHMT2411066
- Bài tập: Case Study 2 — Task Manager
- Repository dự kiến: `case2_KHMT2411066_LeTrucLy`

## Chức năng

- **Tài khoản:** đăng ký, đăng nhập JWT, xem/sửa họ tên, đổi mật khẩu, đăng xuất.
- **Công việc:** tạo/xem/sửa/xóa, trạng thái, độ ưu tiên, ngày bắt đầu/hạn hoàn thành.
- **Giao việc:** nhiều người, chọn người phụ trách chính, chỉ chủ công việc được quản lý giao việc.
- **Chia sẻ:** nhiều người, quyền viewer/editor, sửa và thu hồi quyền; backend xác thực từng thao tác.
- **Thông báo:** lưu trong MongoDB, đánh dấu đã đọc, mở công việc; email khi giao mới, chia sẻ mới, đổi hạn hoặc hoàn thành.
- **Email:** lưu `email_logs` (pending/sent/failed), chủ công việc xem log và gửi lại tối đa 3 lần.
- **Lịch sử:** lưu hoạt động tạo, sửa, giao, chia sẻ, đổi trạng thái.
- **Tìm kiếm nâng cao:** từ khóa, trạng thái, ưu tiên, phạm vi, người phụ trách, sắp xếp.
- **Thống kê:** trạng thái, công việc được giao/phụ trách, sắp đến hạn trong 7 ngày, quá hạn.

## Cài đặt

1. Cài Flutter, Android Studio, Node.js và MongoDB.
2. Trong thư mục `api`, chạy `npm install`.
3. Sao chép `api/.env.example` thành `api/.env` và nhập MongoDB URI, JWT secret và SMTP hợp lệ. **Không đẩy `.env` lên GitHub**.
4. Khởi động backend: `cd api && node server.js`.
5. Tại thư mục gốc Flutter: `flutter pub get` và `flutter run`.
6. Android Emulator sử dụng `http://10.0.2.2:3000` trong `lib/services/api_service.dart`.

## Kiểm tra

- `node --check api/server.js`
- `node --check api/email_service.js`
- `flutter analyze lib`
- Kiểm thử các trường hợp: viewer không được sửa/xóa; editor được sửa nhưng không được quản lý chia sẻ; chỉ owner được giao việc; email/log/notification khi chia sẻ mới; lọc và thống kê.

## API chính

- `/api/register`, `/api/login`, `/api/auth/me`, `/api/auth/change-password`
- `/api/tasks`, `/api/tasks/:id`, `/api/tasks/:id/status`, `/api/tasks/:id/assignees`, `/api/tasks/:id/shares`
- `/api/notifications`, `/api/notifications/unread-count`, `/api/notifications/:id/read`, `/api/notifications/read-all`
- `/api/statistics/tasks`, `/api/statistics/assignments`, `/api/statistics/deadlines`
- `/api/tasks/:id/activities`, `/api/tasks/:id/email-logs`, `/api/email-logs/:id/retry`

## Lưu ý

- Trạng thái sử dụng `pending`, `in_progress`, `completed` để tương thích dữ liệu cũ.
- Cấu trúc thư mục trong tài liệu là **đề xuất**; bản này giữ các file Flutter đang có để tránh phá chức năng cũ.
- Các phần mở rộng như nhắc việc tự động 24 giờ và kiểm thử tích hợp trên máy người dùng cần triển khai/kiểm tra riêng.
- Chưa chạy kiểm thử với MongoDB/SMTP thật trong môi trường tạo bản cập nhật này.
