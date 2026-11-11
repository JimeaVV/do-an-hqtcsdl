# Kịch bản test

Có 2 cách test: chạy script tự động (khoảng 10 giây) hoặc bấm tay trên web theo bảng bên dưới. Hai cách dùng chung mã test (T, D, S, K, G, X), nên chỗ nào script báo lỗi thì mở đúng dòng đó ra bấm lại cho dễ thấy.

## Chuẩn bị

1. Chạy SQL theo thứ tự: `01_tao_bang.sql`, `02_procedure.sql`, `03_trigger.sql`, `03b_nap_du_lieu_lon.sql`, `04_index.sql`.
2. Ở thư mục gốc repo đã có `.venv` và `.env` như README.

## Cách 1: script tự động

```bash
.venv\Scripts\python test\kiem_tra_web.py
```

- Không cần mở web trước, script tự chạy Flask bên trong.
- Script tự tạo dữ liệu riêng tên `TEST ...` và xóa sạch khi xong, chỉ để lại các dòng trong NhatKy.
- Thêm `--giu-lai` để giữ dữ liệu test lại, mở web xem. Thêm `--ai` để test luôn tìm kiếm AI (nạp model nên chậm).
- Cuối cùng in `Kết quả: 48/48 đạt`. Dòng nào lỗi thì in ra mã test và thông báo lỗi.

## Cách 2: bấm tay trên web

Mở web: `.venv\Scripts\python web\app.py` rồi vào http://localhost:5055.

Nên tạo một danh mục, sản phẩm, khách hàng mới để test, đừng dùng dữ liệu demo. Số lượng trong bảng tính theo sản phẩm có tồn kho 10.

### Danh mục, sản phẩm

| Mã | Làm gì | Kết quả đúng | Kiểm tra cái gì |
|---|---|---|---|
| D01 | Danh mục: thêm tên mới | Hiện trong danh sách | `sp_DanhMuc_Them` |
| D02 | Thêm lại đúng tên đó | Báo "Tên danh mục đã tồn tại" | Lỗi 50008 |
| S01 | Sản phẩm, Thêm sản phẩm: giá 1.000.000, tồn 10 | Báo đã thêm, có mã mới | `sp_SanPham_Them` có OUTPUT |
| S02 | Gõ tên sản phẩm vào ô tìm | Ra đúng sản phẩm đó | `sp_SanPham_LayDS` |
| S03 | Thêm sản phẩm giá -5 | Báo lỗi ràng buộc CK_SanPham_Gia, trang không sập | CHECK trong bảng |
| S04 | Sửa giá thành 1.200.000 | Bảng LichSuGia có dòng 1.000.000 -> 1.200.000 | `trg_SanPham_LichSuGia` |
| S05 | Sửa mô tả, giữ nguyên giá | LichSuGia không có thêm dòng | Trigger chỉ ghi khi giá đổi |

Bảng LichSuGia chưa có trang trên web, xem bằng SSMS: `SELECT * FROM LichSuGia WHERE MaSP = <mã>`.

### Khách hàng

| Mã | Làm gì | Kết quả đúng | Kiểm tra cái gì |
|---|---|---|---|
| K01 | Khách hàng, Thêm khách: tên, email mới | Báo đã thêm | `sp_KhachHang_Them` |
| K02 | Thêm khách khác nhưng trùng email | Báo "Email đã tồn tại" | Lỗi 50004 |
| K03 | Bấm Sửa ở một khách, đổi tên | Tên mới hiện trong danh sách | `sp_KhachHang_Sua` |

### Đặt hàng, hủy, thanh toán (phần transaction, quan trọng nhất)

| Mã | Làm gì | Kết quả đúng | Kiểm tra cái gì |
|---|---|---|---|
| G01 | Thêm sản phẩm test vào giỏ, sửa số lượng thành 7, chọn khách, bấm Đặt hàng | Chuyển sang trang chi tiết đơn mới | `sp_DatHang` |
| G02 | Xem lại sản phẩm | Tồn kho còn 3 | Trừ kho trong cùng giao dịch |
| G03 | Mở Nhật ký | Có dòng "Thêm đơn ..." | `trg_DonHang_NhatKy` |
| G04 | Lọc Nhật ký theo Cảnh báo kho | Có dòng "... chỉ còn 3 cái" | `trg_SanPham_CanhBaoKho` |
| G05 | Xem trang chi tiết đơn | Có sản phẩm, tổng 8.400.000 ₫ | `sp_DonHang_LayChiTiet` |
| G06 | Giỏ 2 món: sản phẩm test số lượng 1 và một sản phẩm khác số lượng lớn hơn tồn kho. Đặt hàng | Báo "Không đủ hàng. Giao dịch đã ROLLBACK" | `THROW 50001` trong transaction |
| G07 | Xem lại sản phẩm test | Vẫn còn 3, món đủ hàng cũng không bị trừ | ROLLBACK cả đơn |
| G08 | Đơn hàng, lọc theo khách | Không có đơn mới nào | ROLLBACK cả đơn |
| G09 | Mở đơn ở G01, bấm Hủy đơn | Đơn thành Đã hủy, tồn kho về 10 | `sp_HuyDon` |
| G10 | Mở Nhật ký | Có dòng "trạng thái ChoXuLy -> DaHuy" | Trigger ghi thao tác Sửa |
| G11 | Hủy lại đơn đó (mở 2 tab, hủy ở cả 2) | Tab sau báo lỗi, tồn kho vẫn 10 | Lỗi 50006, không cộng kho 2 lần |
| G12 | Đặt đơn mới 2 cái rồi bấm Thanh toán | Đơn thành Hoàn thành, số tiền 2.400.000 ₫ | `sp_ThanhToan`, tiền do database tự tính |
| G13 | Thanh toán lại đơn đó (2 tab) | Báo lỗi | Lỗi 50006 |
| G14 | Hủy đơn đã thanh toán (2 tab) | Báo lỗi | Lỗi 50006 |

G11, G13, G14: trên web, nút Hủy và Thanh toán ẩn đi khi đơn không còn chờ xử lý. Muốn thấy lỗi thì mở đơn ở 2 tab, bấm ở tab 1 trước rồi bấm ở tab 2.

### Xóa

| Mã | Làm gì | Kết quả đúng | Kiểm tra cái gì |
|---|---|---|---|
| X01 | Xóa khách đã có đơn | Báo "Khách hàng đã có đơn hàng, không thể xóa" | Lỗi 50005 |
| X02 | Xóa khách chưa có đơn | Mất khỏi danh sách | `sp_KhachHang_Xoa` |
| X03 | Xóa sản phẩm đã có đơn | Báo "chỉ được ẩn". Trong SSMS sản phẩm vẫn còn, `DaXoa = 1` | `trg_SanPham_ChanXoa` (INSTEAD OF DELETE) |
| X04 | Tìm lại sản phẩm đó trên web | Không thấy nữa | LayDS lọc DaXoa |
| X05 | Xóa sản phẩm chưa có đơn | Báo "Đã xóa hẳn". Trong SSMS không còn dòng đó | Trigger xóa thật |
| X06 | Xóa danh mục còn sản phẩm | Báo "Danh mục còn sản phẩm, không thể xóa" | Lỗi 50003 |

### Các trang còn lại (chỉ cần mở được, không lỗi)

Tổng quan, Sản phẩm (có phân trang), Đơn hàng (lọc 3 trạng thái), Khách hàng và nút Phân nhóm lại, Nhật ký, Đối tượng CSDL (phải thấy đủ 4 trigger và các index của `04_index.sql`).

Tìm theo nghĩa (AI) mở được, nhưng kết quả chưa có nghĩa cho tới khi dữ liệu sản phẩm thật thay cho "SP demo".

## Sau khi test tay

Dữ liệu test tạo bằng tay vẫn còn trong database. Muốn sạch thì chạy lại 5 file SQL từ đầu.
