/* =====================================================================
   test_02_procedure.sql
   Kịch bản test cho 02_procedure.sql.

   CÁCH DÙNG
   - Chạy trên database sạch (vừa chạy 01 và 02), chạy MỘT LẦN theo thứ tự.
   - Bôi đen TỪNG PHẦN (từ dấu === đến GO) rồi bấm F5. Không bấm F5 cả file.
   - Các lệnh "LỖI MONG ĐỢI" nằm trong batch riêng vì THROW làm dừng batch.
   - Chụp màn hình kết quả để đưa vào báo cáo.
   ===================================================================== */
USE ShopDB;
GO

/* ===== 1. DANH MỤC ================================================== */
DECLARE @dm INT;
EXEC sp_DanhMuc_Them @TenDanhMuc = N'Điện thoại', @MaDanhMuc = @dm OUTPUT;
EXEC sp_DanhMuc_Them @TenDanhMuc = N'Laptop',     @MaDanhMuc = @dm OUTPUT;
EXEC sp_DanhMuc_Sua  @MaDanhMuc = @dm, @TenDanhMuc = N'Laptop & PC';
EXEC sp_DanhMuc_LayDS;
-- MONG ĐỢI: 2 dòng "Điện thoại" và "Laptop & PC", SoSanPham = 0, TongSo = 2
GO

-- LỖI MONG ĐỢI: Msg 50008 "Tên danh mục đã tồn tại"
DECLARE @dm INT;
EXEC sp_DanhMuc_Them @TenDanhMuc = N'Điện thoại', @MaDanhMuc = @dm OUTPUT;
GO

/* ===== 2. SẢN PHẨM ================================================== */
DECLARE @dt INT = (SELECT MaDanhMuc FROM DanhMuc WHERE TenDanhMuc = N'Điện thoại');
DECLARE @sp INT;

EXEC sp_SanPham_Them @MaDanhMuc=@dt, @TenSP=N'Điện thoại A', @MoTa=N'Hàng test',
                     @Gia=10000000, @TonKho=10, @MaSP=@sp OUTPUT;
EXEC sp_SanPham_Them @MaDanhMuc=@dt, @TenSP=N'Điện thoại B', @Gia=5000000, @TonKho=1,  @MaSP=@sp OUTPUT;
EXEC sp_SanPham_Them @MaDanhMuc=@dt, @TenSP=N'Điện thoại C', @Gia=2000000, @TonKho=10, @MaSP=@sp OUTPUT;

-- Sửa giá C từ 2.000.000 lên 2.500.000 (sau khi có trigger sẽ ghi LichSuGia)
USE ShopDB;
DECLARE @c  INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại C');
DECLARE @dt INT = (SELECT MaDanhMuc FROM DanhMuc WHERE TenDanhMuc = N'Điện thoại');
EXEC sp_SanPham_Sua @MaSP=@c, @MaDanhMuc=@dt, @TenSP=N'Điện thoại C',
                    @Gia=2500000, @TonKho=10;

-- Phân trang: trang 1 có 2 dòng, trang 2 có 1 dòng, TongSo = 3

USE ShopDB;

-- Phân trang: trang 1 có 2 dòng, trang 2 có 1 dòng, TongSo = 3
EXEC sp_SanPham_LayDS @TuKhoa=N'Điện thoại', @Trang=1, @KichThuoc=2;
EXEC sp_SanPham_LayDS @TuKhoa=N'Điện thoại', @Trang=2, @KichThuoc=2;

-- Lấy theo mã: tra mã của "Điện thoại C" theo tên
DECLARE @sp INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại C');
EXEC sp_SanPham_LayTheoMa @MaSP=@sp;      -- MONG ĐỢI: Điện thoại C, giá 2.500.000
GO

/* ===== 3. KHÁCH HÀNG =============================================== */
DECLARE @kh INT;
EXEC sp_KhachHang_Them @HoTen=N'Nguyễn Văn A', @Email=N'a@test.com', @SDT='0900000001', @MaKH=@kh OUTPUT;
EXEC sp_KhachHang_Them @HoTen=N'Trần Thị B',   @Email=N'b@test.com', @MaKH=@kh OUTPUT;
EXEC sp_KhachHang_Sua  @MaKH=@kh, @HoTen=N'Trần Thị Bích', @Email=N'b@test.com', @SDT='0900000002';
EXEC sp_KhachHang_LayDS;                  -- MONG ĐỢI: 2 khách
EXEC sp_KhachHang_LayDS @TuKhoa=N'Bích';  -- MONG ĐỢI: 1 khách
GO

-- LỖI MONG ĐỢI: Msg 50004 "Email đã tồn tại"
DECLARE @kh INT;
EXEC sp_KhachHang_Them @HoTen=N'Trùng Email', @Email=N'a@test.com', @MaKH=@kh OUTPUT;
GO

/* ===== 4. ĐẶT HÀNG ================================================== */
-- Tồn kho trước: A = 10, C = 10
USE ShopDB;
GO
SELECT TenSP, TonKho FROM SanPham WHERE TenSP IN (N'Điện thoại A', N'Điện thoại C');

DECLARE @kh  INT = (SELECT MaKH FROM KhachHang WHERE Email = N'a@test.com');
DECLARE @a   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại A');
DECLARE @c   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại C');
DECLARE @gio NVARCHAR(MAX) =
    N'[{"MaSP":' + CAST(@a AS NVARCHAR(20)) + N',"SoLuong":2},'
  + N'{"MaSP":'  + CAST(@c AS NVARCHAR(20)) + N',"SoLuong":1}]';
DECLARE @don INT;

EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;
SELECT @don AS MaDonVuaTao;
EXEC sp_DonHang_LayChiTiet @MaDon=@don;
-- MONG ĐỢI: đơn ChoXuLy, 2 dòng chi tiết, tổng tiền = 2*10.000.000 + 1*2.500.000 = 22.500.000
SELECT TenSP, TonKho FROM SanPham WHERE TenSP IN (N'Điện thoại A', N'Điện thoại C');
-- MONG ĐỢI: A = 8, C = 9
GO

-- LỖI MONG ĐỢI: Msg 50001 "Không đủ hàng". A hợp lệ nhưng C đòi 999 -> hủy CẢ đơn.
USE ShopDB;
GO
DECLARE @kh  INT = (SELECT MaKH FROM KhachHang WHERE Email = N'a@test.com');
DECLARE @a   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại A');
DECLARE @c   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại C');
DECLARE @gio NVARCHAR(MAX) =
    N'[{"MaSP":' + CAST(@a AS NVARCHAR(20)) + N',"SoLuong":1},'
  + N'{"MaSP":'  + CAST(@c AS NVARCHAR(20)) + N',"SoLuong":999}]';
DECLARE @don INT;
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;
GO

-- Kiểm tra rollback: A vẫn = 8 (không bị trừ), số đơn vẫn là 1
USE ShopDB;
GO
SELECT TenSP, TonKho FROM SanPham WHERE TenSP IN (N'Điện thoại A', N'Điện thoại C');
SELECT COUNT(*) AS SoDon FROM DonHang;
GO

-- LỖI MONG ĐỢI: Msg 50007 "Giỏ hàng không hợp lệ"
USE ShopDB;
GO
DECLARE @don INT;
EXEC sp_DatHang @MaKH=1, @GioHang=N'[]', @MaDon=@don OUTPUT;
GO

/* ===== 5. HỦY ĐƠN =================================================== */
USE ShopDB;
GO
DECLARE @don INT = (SELECT MAX(MaDon) FROM DonHang);   -- đơn vừa tạo ở mục 4
EXEC sp_HuyDon @MaDon=@don;
SELECT MaDon, TrangThai FROM DonHang WHERE MaDon=@don;          -- MONG ĐỢI: DaHuy
SELECT TenSP, TonKho FROM SanPham WHERE TenSP IN (N'Điện thoại A', N'Điện thoại C');
-- MONG ĐỢI: tồn kho được cộng lại, A = 10, C = 10
GO

-- LỖI MONG ĐỢI: Msg 50006 (đơn đã hủy, không hủy lần hai)
USE ShopDB;
GO
DECLARE @don INT = (SELECT MAX(MaDon) FROM DonHang);
EXEC sp_HuyDon @MaDon=@don;
GO

/* ===== 6. THANH TOÁN ================================================ */
-- Tạo đơn mới (A x1, C x2) rồi thanh toán
USE ShopDB;
GO
DECLARE @kh  INT = (SELECT MaKH FROM KhachHang WHERE Email = N'a@test.com');
DECLARE @a   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại A');
DECLARE @c   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại C');
DECLARE @gio NVARCHAR(MAX) =
    N'[{"MaSP":' + CAST(@a AS NVARCHAR(20)) + N',"SoLuong":1},'
  + N'{"MaSP":'  + CAST(@c AS NVARCHAR(20)) + N',"SoLuong":2}]';
DECLARE @don INT, @tt INT;

EXEC sp_DatHang   @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;
EXEC sp_ThanhToan @MaDon=@don, @PhuongThuc=N'Chuyển khoản', @MaTT=@tt OUTPUT;

SELECT MaDon, TrangThai FROM DonHang WHERE MaDon=@don;   -- MONG ĐỢI: HoanThanh
SELECT * FROM ThanhToan WHERE MaTT=@tt;                  -- MONG ĐỢI: SoTien = 15.000.000
GO

-- LỖI MONG ĐỢI: Msg 50006 (đơn đã thanh toán, không thanh toán lần hai)
USE ShopDB;
GO
DECLARE @don INT = (SELECT MAX(MaDon) FROM DonHang), @tt INT;
EXEC sp_ThanhToan @MaDon=@don, @PhuongThuc=N'Tiền mặt', @MaTT=@tt OUTPUT;
GO

/* ===== 7. DANH SÁCH ĐƠN ============================================ */
USE ShopDB;
GO
EXEC sp_DonHang_LayDS;                                    -- MONG ĐỢI: 2 đơn (DaHuy, HoanThanh)
EXEC sp_DonHang_LayDS @TrangThai = N'HoanThanh';          -- MONG ĐỢI: 1 đơn
EXEC sp_DonHang_LayDS @MaKH = 1, @Trang = 1, @KichThuoc = 1;  -- 1 dòng, TongSo = 2
GO


/* ===== 8. DEMO HAI NGƯỜI MUA MÓN CUỐI CÙNG (2 cửa sổ) ===============
   Chuẩn bị: chạy lệnh dưới để biết MaSP của "Điện thoại B" (TonKho = 1)
   và MaKH của hai khách. Sau đó điền số vào @b, @kh bên dưới.
   Cố ý KHÔNG tra cứu bằng tên trong cửa sổ demo, vì SELECT có thể bị
   khóa chờ và làm lệch kết quả demo. */
USE ShopDB;
GO
SELECT MaSP, TenSP, TonKho FROM SanPham WHERE TenSP = N'Điện thoại B';
SELECT MaKH, HoTen FROM KhachHang;
GO

--- CỬA SỔ 1 (New Query thứ nhất): bôi đen và F5, CHƯA COMMIT ---
USE ShopDB;
BEGIN TRAN;
DECLARE @b INT = 2, @kh INT = 1, @don INT;   -- thay bằng số thật
DECLARE @gio NVARCHAR(MAX) = N'[{"MaSP":' + CAST(@b AS NVARCHAR(20)) + N',"SoLuong":1}]';
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;
SELECT @don AS DonCuaCuaSo1;
-- (để yên, chưa COMMIT)
COMMIT;

/* --- CỬA SỔ 2 (New Query thứ hai): bôi đen và F5 -> sẽ ĐỨNG CHỜ ---
DECLARE @b INT = 2, @kh INT = 2, @don INT;   -- cùng @b, khách khác
DECLARE @gio NVARCHAR(MAX) = N'[{"MaSP":' + CAST(@b AS NVARCHAR(20)) + N',"SoLuong":1}]';
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;
*/

/* --- QUAY LẠI CỬA SỔ 1: chạy ---
COMMIT;
-- Cửa sổ 2 lập tức báo Msg 50001 "Không đủ hàng".
*/
-- Kiểm tra: TonKho của B = 0 (không âm), chỉ có 1 đơn mới chứa B
USE ShopDB;
SELECT TenSP, TonKho FROM SanPham WHERE TenSP = N'Điện thoại B';
SELECT ct.MaDon, dh.MaKH FROM ChiTietDonHang ct
JOIN DonHang dh ON dh.MaDon = ct.MaDon WHERE ct.MaSP = 2;


/* ===== 9. THỐNG KÊ, NHẬT KÝ, ĐỐI TƯỢNG CSDL ======================== */
USE ShopDB;
EXEC sp_ThongKe_Dashboard;   -- 3 bảng kết quả: tổng quan, top 5 bán chạy, doanh thu theo tháng
EXEC sp_NhatKy_LayDS;        -- rỗng nếu chưa tạo 03_trigger.sql; có dữ liệu sau khi tạo
EXEC sp_DoiTuongCSDL;        -- 24 procedure; trigger và index xuất hiện khi đã chạy 03, 04
GO

/* ===== 10. AI ======================================================= */
USE ShopDB;
EXEC sp_TinhRFM;
SELECT * FROM KhachHang_PhanNhom;      -- MONG ĐỢI: có dòng cho khách đã có đơn HoanThanh

-- Giả lập việc Lợi gán nhóm, rồi xem thống kê
USE ShopDB;
UPDATE KhachHang_PhanNhom SET Nhom = N'VIP' WHERE MaKH = 1;
EXEC sp_PhanNhom_ThongKe;

-- Lấy sản phẩm theo danh sách mã, đúng thứ tự đưa vào (sửa số cho khớp MaSP thật)
USE ShopDB;
EXEC sp_SanPham_LayTheoDS @DSMaSP = N'[3,1,2]';   -- MONG ĐỢI: C, A, B (đúng thứ tự)
GO

-- LỖI MONG ĐỢI: Msg 50007
USE ShopDB;
EXEC sp_SanPham_LayTheoDS @DSMaSP = N'khong phai json';
GO

/* ===== 11. XÓA ====================================================== */
-- 11a. Sản phẩm CHƯA có đơn: xóa thật. MONG ĐỢI: KetQua = DaXoa
USE ShopDB;
DECLARE @dt INT = (SELECT MaDanhMuc FROM DanhMuc WHERE TenDanhMuc = N'Điện thoại');
DECLARE @d INT;
EXEC sp_SanPham_Them @MaDanhMuc=@dt, @TenSP=N'Sản phẩm xóa thử', @Gia=1000, @TonKho=5, @MaSP=@d OUTPUT;
EXEC sp_SanPham_Xoa @MaSP=@d;
SELECT COUNT(*) AS ConTonTai FROM SanPham WHERE MaSP=@d;   -- MONG ĐỢI: 0
GO

-- 11b. Sản phẩm ĐÃ có đơn (Điện thoại A).
--   Trước khi có 03_trigger.sql: báo lỗi khóa ngoại (đây là lý do cần trigger).
--   Sau khi có trigger:          KetQua = DaAn, SanPham.DaXoa = 1.
DECLARE @a INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại A');
EXEC sp_SanPham_Xoa @MaSP=@a;
GO
SELECT MaSP, TenSP, DaXoa FROM SanPham WHERE TenSP = N'Điện thoại A';
EXEC sp_SanPham_LayDS @TuKhoa = N'Điện thoại A';  -- MONG ĐỢI (sau trigger): không còn hiện ra
GO

-- 11c. Danh mục còn sản phẩm. LỖI MONG ĐỢI: Msg 50003
USE ShopDB;
DECLARE @dt INT = (SELECT MaDanhMuc FROM DanhMuc WHERE TenDanhMuc = N'Điện thoại');
EXEC sp_DanhMuc_Xoa @MaDanhMuc=@dt;
GO

-- 11d. Khách đã có đơn. LỖI MONG ĐỢI: Msg 50005
USE ShopDB;
EXEC sp_KhachHang_Xoa @MaKH = 1;
GO

-- 11e. Khách chưa có đơn và danh mục rỗng: xóa được, không lỗi
USE ShopDB;
DECLARE @kh INT, @dm INT;
EXEC sp_KhachHang_Them @HoTen=N'Khách xóa thử', @Email=N'xoa@test.com', @MaKH=@kh OUTPUT;
EXEC sp_KhachHang_Xoa  @MaKH=@kh;
EXEC sp_DanhMuc_Them   @TenDanhMuc=N'Danh mục xóa thử', @MaDanhMuc=@dm OUTPUT;
EXEC sp_DanhMuc_Xoa    @MaDanhMuc=@dm;
GO