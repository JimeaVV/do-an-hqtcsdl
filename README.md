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
| Vinh | Bảng, procedure, giao dịch, trigger, index | Chương 2, 3, 5 và phần index của chương 4 |
| Lợi | Dữ liệu, tìm kiếm ngữ nghĩa, phân nhóm khách hàng | Chương 6 và phần dữ liệu của chương 4 |
| Giang | Sơ đồ, web, ghép báo cáo | Chương 1, 7 |

## Chạy trên máy

1. Trong SSMS, chạy lần lượt `sql/01_tao_bang.sql`, `02_procedure.sql`, `03_trigger.sql`, `03b_nap_du_lieu_lon.sql`, `04_index.sql`.
2. Tạo file `.env` ở thư mục gốc (không đưa lên repo):

   ```
   DB_DRIVER=ODBC Driver 18 for SQL Server
   DB_SERVER=localhost
   DB_NAME=ShopDB
   DB_TRUSTED_CONNECTION=yes
   DB_TRUST_SERVER_CERTIFICATE=yes
   ```

   Bản SQL Server Express thì đổi `DB_SERVER=localhost\SQLEXPRESS`.
3. Cài thư viện và chạy AI lần đầu (lần đầu tải model khoảng vài trăm MB):

   ```
   python -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   .venv\Scripts\python ai\tao_embedding.py
   .venv\Scripts\python ai\phan_nhom.py
   ```

4. Chạy web rồi mở http://localhost:5055

   ```
   .venv\Scripts\python web\app.py
   ```

Khi sản phẩm thay đổi, chạy lại `ai\tao_embedding.py` rồi khởi động lại web để tìm kiếm AI thấy dữ liệu mới.

## Quy tắc làm chung

- Mọi thay đổi CSDL đều lưu thành file `.sql` có số thứ tự trong `sql/`.
- Web chỉ gọi stored procedure, không viết SQL trực tiếp.
- Báo nhóm trước khi đổi tên cột hoặc tham số procedure.
- Không đưa mật khẩu, file `.env` hay dữ liệu lớn lên repo.
