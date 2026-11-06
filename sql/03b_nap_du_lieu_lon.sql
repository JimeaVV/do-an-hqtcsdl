/* =====================================================================
   03b_nap_du_lieu_lon.sql
   Sinh dữ liệu lớn để đo index (thay cho dữ liệu của Lợi).
   Chạy MỘT LẦN, sau 03_trigger.sql và TRƯỚC 04_index.sql.
   Quy mô mặc định: 20 danh mục, 5.000 sản phẩm, 20.000 khách,
   500.000 đơn, khoảng 1 triệu dòng chi tiết. Mất vài phút.
   Chạy từng batch (bôi đen đến GO) theo thứ tự A -> B -> C.
   ===================================================================== */
USE ShopDB;
GO

/* ===== A. Tắt trigger ghi nhật ký để nạp nhanh ===== */
DISABLE TRIGGER trg_DonHang_NhatKy     ON DonHang;
DISABLE TRIGGER trg_SanPham_LichSuGia  ON SanPham;
DISABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;
GO

/* ===== B. Nạp dữ liệu ===== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @SoDM INT = 20, @SoSP INT = 5000, @SoKH INT = 20000, @SoDon INT = 500000;

-- Chống chạy 2 lần
IF EXISTS (SELECT 1 FROM KhachHang WHERE Email LIKE N'kh%@demo.vn')
    THROW 50100, N'Dữ liệu lớn đã được nạp rồi, không chạy lại.', 1;

-- Bảng số 1..N dùng chung
SELECT TOP (@SoDon) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
INTO #So
FROM sys.all_objects a CROSS JOIN sys.all_objects b CROSS JOIN sys.all_objects c;

-- 1. Danh mục
INSERT DanhMuc(TenDanhMuc)
SELECT N'Danh mục demo ' + RIGHT('00' + CAST(n AS VARCHAR(5)), 2)
FROM #So WHERE n <= @SoDM;

SELECT ROW_NUMBER() OVER (ORDER BY MaDanhMuc) AS stt, MaDanhMuc
INTO #DM FROM DanhMuc WHERE TenDanhMuc LIKE N'Danh mục demo %';

-- 2. Sản phẩm (giá 100.000 .. 30.000.000, tồn kho 0..500)
INSERT SanPham(MaDanhMuc, TenSP, MoTa, Gia, TonKho, DaXoa)
SELECT dm.MaDanhMuc,
       N'SP demo ' + RIGHT('00000' + CAST(s.n AS VARCHAR(8)), 5),
       N'Mô tả sản phẩm demo',
       (100 + ABS(CHECKSUM(NEWID())) % 29900) * 1000,
       ABS(CHECKSUM(NEWID())) % 501,
       0
FROM #So s JOIN #DM dm ON dm.stt = ((s.n - 1) % @SoDM) + 1
WHERE s.n <= @SoSP;

SELECT ROW_NUMBER() OVER (ORDER BY MaSP) AS stt, MaSP, Gia
INTO #SP FROM SanPham WHERE TenSP LIKE N'SP demo %';

-- 3. Khách hàng
INSERT KhachHang(HoTen, Email, SDT, NgayTao)
SELECT N'Khách demo ' + CAST(n AS NVARCHAR(10)),
       N'kh' + CAST(n AS NVARCHAR(10)) + N'@demo.vn',
       '09' + RIGHT('00000000' + CAST(n AS VARCHAR(10)), 8),
       DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 365, '2022-01-01')
FROM #So WHERE n <= @SoKH;

SELECT ROW_NUMBER() OVER (ORDER BY MaKH) AS stt, MaKH
INTO #KH FROM KhachHang WHERE Email LIKE N'kh%@demo.vn';

-- 4. Đơn hàng: ngày 2023-01-01 .. 2026-11-06; 5% ChoXuLy, 15% DaHuy, 80% HoanThanh
SELECT s.n,
       kh.MaKH,
       DATEADD(MINUTE, ABS(CHECKSUM(NEWID())) % (1405 * 1440), CAST('2023-01-01' AS DATETIME2)) AS NgayDat,
       CASE WHEN r.p < 5 THEN N'ChoXuLy' WHEN r.p < 20 THEN N'DaHuy' ELSE N'HoanThanh' END AS TrangThai,
       1 + ABS(CHECKSUM(NEWID())) % 3 AS SoDong,
       1 + ABS(CHECKSUM(NEWID())) % @SoSP AS Goc,
       1 + ABS(CHECKSUM(NEWID())) % ((@SoSP - 1) / 2) AS Buoc
INTO #Don
FROM #So s
CROSS APPLY (SELECT ABS(CHECKSUM(NEWID())) % 100 AS p) r
JOIN #KH kh ON kh.stt = 1 + ABS(CHECKSUM(s.n * 7919)) % @SoKH
WHERE s.n <= @SoDon;

DECLARE @Dau INT = ISNULL((SELECT MAX(MaDon) FROM DonHang), 0);

INSERT DonHang(MaKH, NgayDat, TrangThai)
SELECT MaKH, NgayDat, TrangThai FROM #Don ORDER BY n;

-- 5. Chi tiết đơn: 1-3 dòng/đơn, sản phẩm khác nhau trong cùng đơn
INSERT ChiTietDonHang(MaDon, MaSP, SoLuong, DonGia)
SELECT @Dau + d.n, sp.MaSP, 1 + ABS(CHECKSUM(NEWID())) % 5, sp.Gia
FROM #Don d
CROSS JOIN (VALUES (0),(1),(2)) k(k)
JOIN #SP sp ON sp.stt = ((d.Goc - 1 + k.k * d.Buoc) % @SoSP) + 1
WHERE k.k < d.SoDong;

UPDATE STATISTICS DonHang; UPDATE STATISTICS ChiTietDonHang;
UPDATE STATISTICS SanPham; UPDATE STATISTICS KhachHang;

-- Tóm tắt
SELECT (SELECT COUNT(*) FROM DanhMuc)       AS DanhMuc,
       (SELECT COUNT(*) FROM SanPham)       AS SanPham,
       (SELECT COUNT(*) FROM KhachHang)     AS KhachHang,
       (SELECT COUNT(*) FROM DonHang)       AS DonHang,
       (SELECT COUNT(*) FROM ChiTietDonHang) AS ChiTietDonHang;
GO

/* ===== C. Bật lại trigger (LUÔN chạy, kể cả khi B báo lỗi) ===== */
ENABLE TRIGGER trg_DonHang_NhatKy     ON DonHang;
ENABLE TRIGGER trg_SanPham_LichSuGia  ON SanPham;
ENABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;

SELECT name, is_disabled FROM sys.triggers WHERE parent_class = 1;  -- cả 4 phải = 0
GO
