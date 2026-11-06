# Đồ án Nguyên lý Hệ quản trị CSDL

Website thương mại điện tử dùng SQL Server, Python Flask và Bootstrap.

## Cấu trúc

- `sql/`: script tạo CSDL, chạy theo số thứ tự
- `data/`: script sinh dữ liệu
- `ai/`: tìm kiếm ngữ nghĩa và phân nhóm khách hàng
- `web/`: ứng dụng Flask
- `baocao/`: báo cáo và hình chụp

## Phân công

| Thành viên | Phần việc | Báo cáo |
|---|---|---|
| A | ERD, bảng, procedure, giao dịch, trigger | Chương 2, 3, 5 |
| B | Sinh dữ liệu, index, AI | Chương 4, 6 |
| C | Web, ghép báo cáo | Chương 1, 7 |

## Quy tắc làm chung

- Mọi thay đổi CSDL đều lưu thành file `.sql` có số thứ tự trong `sql/`.
- Web chỉ gọi stored procedure, không viết SQL trực tiếp.
- Báo nhóm trước khi đổi tên cột hoặc tham số procedure.
- Không đưa mật khẩu, file `.env` hay dữ liệu lớn lên repo.
