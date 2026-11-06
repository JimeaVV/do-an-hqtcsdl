/* =====================================================================
   test_03_trigger.sql
   Kịch bản test cho 03_trigger.sql.

   CÁCH DÙNG
   - Chạy sau khi đã chạy test_02_procedure.sql (cần có sản phẩm A, B, C,
     khách a@test.com). Chạy MỘT LẦN, theo thứ tự.
   - Bôi đen từng mục (từ dòng ===== đến GO) rồi F5, như file test trước.
   - Mục có "LỖI MONG ĐỢI" nằm trong batch riêng.
   - Chụp kết quả các bảng SanPham, LichSuGia, NhatKy cho báo cáo.
   ===================================================================== */
USE ShopDB;
GO

/* ===== 0. Kiểm tra trigger đã được tạo ============================== */
SELECT name, OBJECT_NAME(parent_id) AS bang, is_instead_of_trigger
FROM sys.triggers WHERE parent_class = 1 ORDER BY name;
-- MONG ĐỢI: 4 dòng. trg_SanPham_ChanXoa có is_instead_of_trigger = 1.
GO

/* ===== 1. trg_SanPham_LichSuGia ===================================== */
-- 1a. Đổi giá C từ 2.500.000 lên 2.600.000 (giữ nguyên tồn kho hiện tại)
USE ShopDB;
GO
DECLARE @c  INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại C');
DECLARE @dt INT = (SELECT MaDanhMuc FROM DanhMuc WHERE TenDanhMuc = N'Điện thoại');
DECLARE @tk INT = (SELECT TonKho FROM SanPham WHERE MaSP = @c);

EXEC sp_SanPham_Sua @MaSP=@c, @MaDanhMuc=@dt, @TenSP=N'Điện thoại C', @Gia=2600000, @TonKho=@tk;
-- 1b. Sửa lần nữa với ĐÚNG giá đó: không được ghi thêm dòng
USE ShopDB
EXEC sp_SanPham_Sua @MaSP=@c, @MaDanhMuc=@dt, @TenSP=N'Điện thoại C', @Gia=2600000, @TonKho=@tk;

SELECT ls.MaLS, sp.TenSP, ls.GiaCu, ls.GiaMoi, ls.NgayDoi
FROM LichSuGia ls JOIN SanPham sp ON sp.MaSP = ls.MaSP ORDER BY ls.MaLS;
-- MONG ĐỢI: đúng 1 dòng: Điện thoại C, GiaCu 2500000, GiaMoi 2600000
GO

-- 1c. UPDATE nhiều dòng cùng lúc: tăng giá A và C thêm 1.000
USE ShopDB;
UPDATE SanPham SET Gia = Gia + 1000
WHERE TenSP IN (N'Điện thoại A', N'Điện thoại C');

SELECT ls.MaLS, sp.TenSP, ls.GiaCu, ls.GiaMoi
FROM LichSuGia ls JOIN SanPham sp ON sp.MaSP = ls.MaSP ORDER BY ls.MaLS;
-- MONG ĐỢI: tổng 3 dòng; thêm 2 dòng mới (A: 10000000 -> 10001000,
--           C: 2600000 -> 2601000). Cả hai sản phẩm đều được ghi.
GO

-- 1d. Trả giá về như ban đầu (ghi thêm 2 dòng lịch sử)
USE ShopDB;
UPDATE SanPham SET Gia = CASE TenSP WHEN N'Điện thoại A' THEN 10000000
                                    WHEN N'Điện thoại C' THEN 2500000 END
WHERE TenSP IN (N'Điện thoại A', N'Điện thoại C');

SELECT TenSP, Gia FROM SanPham WHERE TenSP IN (N'Điện thoại A', N'Điện thoại C');
SELECT COUNT(*) AS TongDongLichSu FROM LichSuGia;     -- MONG ĐỢI: 5
GO

/* ===== 2. trg_DonHang_NhatKy ======================================== */
-- 2a. Tạo đơn rồi hủy: ghi 1 dòng Them và 1 dòng Sua
USE ShopDB
DECLARE @kh  INT = (SELECT MaKH FROM KhachHang WHERE Email = N'a@test.com');
DECLARE @a   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại A');
DECLARE @gio NVARCHAR(MAX) = N'[{"MaSP":' + CAST(@a AS NVARCHAR(20)) + N',"SoLuong":1}]';
DECLARE @don INT;
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;
EXEC sp_HuyDon  @MaDon=@don;

EXEC sp_NhatKy_LayDS @Bang = N'DonHang';
-- MONG ĐỢI (mới nhất trước):
--   Sua  "Sửa đơn N: trạng thái ChoXuLy -> DaHuy"
--   Them "Thêm đơn N của khách 1, trạng thái ChoXuLy"
-- (các đơn 1, 2, 3 tạo trước khi có trigger nên không có dòng nhật ký)
GO

-- 2b. Thêm 2 đơn trong MỘT lệnh rồi xóa cả 2 trong MỘT lệnh (kiểm tra nhiều dòng)
USE ShopDB
DECLARE @t TABLE (MaDon INT);
INSERT DonHang(MaKH) OUTPUT inserted.MaDon INTO @t(MaDon) VALUES (1), (2);
DELETE FROM DonHang WHERE MaDon IN (SELECT MaDon FROM @t);

EXEC sp_NhatKy_LayDS @Bang = N'DonHang', @KichThuoc = 4;
-- MONG ĐỢI: 4 dòng mới nhất = 2 dòng Xoa rồi 2 dòng Them, đủ cho cả 2 đơn
-- (nếu trigger dùng biến thay vì JOIN thì chỉ ghi được 1 đơn)
GO

/* ===== 3. trg_SanPham_CanhBaoKho ==================================== */
-- Kho C đang là 8. Đặt 4 cái -> còn 4 (xuống dưới 5): ghi cảnh báo.
-- Đặt thêm 1 cái -> còn 3 (đã dưới 5 từ trước): KHÔNG ghi thêm.
USE ShopDB;
GO

DECLARE @kh  INT = (SELECT MaKH FROM KhachHang WHERE Email = N'a@test.com');
DECLARE @c   INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Điện thoại C');
DECLARE @gio NVARCHAR(MAX);
DECLARE @d1 INT, @d2 INT;

SET @gio = N'[{"MaSP":' + CAST(@c AS NVARCHAR(20)) + N',"SoLuong":4}]';
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@d1 OUTPUT;
SELECT TenSP, TonKho FROM SanPham WHERE MaSP=@c;               -- MONG ĐỢI: C = 4
EXEC sp_NhatKy_LayDS @ThaoTac = N'CanhBaoKho';                 -- MONG ĐỢI: 1 dòng

SET @gio = N'[{"MaSP":' + CAST(@c AS NVARCHAR(20)) + N',"SoLuong":1}]';
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@d2 OUTPUT;
SELECT TenSP, TonKho FROM SanPham WHERE MaSP=@c;               -- MONG ĐỢI: C = 3
SELECT COUNT(*) AS SoCanhBao FROM NhatKy WHERE ThaoTac = N'CanhBaoKho';  -- MONG ĐỢI: 1

EXEC sp_HuyDon @MaDon=@d1;
EXEC sp_HuyDon @MaDon=@d2;
SELECT TenSP, TonKho FROM SanPham WHERE MaSP=@c;               -- MONG ĐỢI: C = 8
GO

/* ===== 4. trg_SanPham_ChanXoa ======================================= */
-- 4a. Sản phẩm CHƯA có đơn, có dòng embedding: xóa thật cả hai
Use ShopDB
DECLARE @dt INT = (SELECT MaDanhMuc FROM DanhMuc WHERE TenDanhMuc = N'Điện thoại');
DECLARE @x INT;
EXEC sp_SanPham_Them @MaDanhMuc=@dt, @TenSP=N'Trigger thử 1', @Gia=1000, @TonKho=10, @MaSP=@x OUTPUT;
INSERT SanPham_Embedding(MaSP, Vector) VALUES (@x, 0x0102030405);

EXEC sp_SanPham_Xoa @MaSP=@x;                                   -- MONG ĐỢI: KetQua = DaXoa
SELECT (SELECT COUNT(*) FROM SanPham           WHERE MaSP=@x) AS SanPham_ConLai,
       (SELECT COUNT(*) FROM SanPham_Embedding WHERE MaSP=@x) AS Embedding_ConLai;
-- MONG ĐỢI: 0 và 0
GO

-- 4b. Xóa NHIỀU dòng trong một lệnh: X chưa có đơn, Y đã có đơn
DECLARE @dt INT = (SELECT MaDanhMuc FROM DanhMuc WHERE TenDanhMuc = N'Điện thoại');
DECLARE @kh INT = (SELECT MaKH FROM KhachHang WHERE Email = N'a@test.com');
DECLARE @x INT, @y INT, @don INT;
EXEC sp_SanPham_Them @MaDanhMuc=@dt, @TenSP=N'Trigger thử X', @Gia=1000, @TonKho=10, @MaSP=@x OUTPUT;
EXEC sp_SanPham_Them @MaDanhMuc=@dt, @TenSP=N'Trigger thử Y', @Gia=2000, @TonKho=10, @MaSP=@y OUTPUT;

DECLARE @gio NVARCHAR(MAX) = N'[{"MaSP":' + CAST(@y AS NVARCHAR(20)) + N',"SoLuong":1}]';
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;   -- Y đã có đơn

DELETE FROM SanPham WHERE MaSP IN (@x, @y);

SELECT MaSP, TenSP, DaXoa FROM SanPham WHERE TenSP IN (N'Trigger thử X', N'Trigger thử Y');
-- MONG ĐỢI: chỉ còn 1 dòng, Y với DaXoa = 1. X đã bị xóa thật.
GO

-- 4c. Sản phẩm bị ẩn: không hiện ra, nhưng đơn cũ vẫn đủ thông tin
Use ShopDB
EXEC sp_SanPham_LayDS @TuKhoa = N'Trigger thử';
-- MONG ĐỢI: 0 dòng (Y đã bị ẩn)
Use ShopDB
DECLARE @y INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Trigger thử Y');
DECLARE @d INT = (SELECT MaDon FROM ChiTietDonHang WHERE MaSP = @y);
EXEC sp_DonHang_LayChiTiet @MaDon = @d;
-- MONG ĐỢI: bảng chi tiết vẫn có dòng "Trigger thử Y", đơn giá 2000
GO

-- 4d. Không đặt hàng được sản phẩm đã ẩn. LỖI MONG ĐỢI: Msg 50001
Use ShopDB
DECLARE @kh INT = (SELECT MaKH FROM KhachHang WHERE Email = N'a@test.com');
DECLARE @y  INT = (SELECT MaSP FROM SanPham WHERE TenSP = N'Trigger thử Y');
DECLARE @gio NVARCHAR(MAX) = N'[{"MaSP":' + CAST(@y AS NVARCHAR(20)) + N',"SoLuong":1}]';
DECLARE @don INT;
EXEC sp_DatHang @MaKH=@kh, @GioHang=@gio, @MaDon=@don OUTPUT;
GO

-- 4e. Chạy lại mục 11b của test_02_procedure.sql (xóa "Điện thoại A")
--     MONG ĐỢI: KetQua = DaAn, DaXoa = 1, không còn lỗi khóa ngoại.
--     (Lưu ý: A bị ẩn nên các mục test 02 dùng A sẽ không chạy lại được.)

/* ===== 5. Tổng kết để chụp cho báo cáo ============================== */
Use ShopDB;
SELECT MaSP, TenSP, Gia, TonKho, DaXoa FROM SanPham ORDER BY MaSP;
SELECT * FROM LichSuGia ORDER BY MaLS;
SELECT * FROM NhatKy ORDER BY MaNK;
EXEC sp_DoiTuongCSDL;     -- MONG ĐỢI: 24 procedure + 4 trigger
GO
