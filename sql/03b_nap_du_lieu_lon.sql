/* =====================================================================
   03b_nap_du_lieu_lon.sql
   Sinh dữ liệu lớn để đo index (thay cho dữ liệu của Lợi).
   Chạy MỘT LẦN, sau 03_trigger.sql và TRƯỚC 04_index.sql.
   Quy mô mặc định: 20 danh mục, 5.000 sản phẩm, 20.000 khách,
   500.000 đơn, khoảng 1 triệu dòng chi tiết. Mất vài phút.
   Chạy từng batch (bôi đen đến GO) theo thứ tự A -> B -> C.

   CÁC ĐIỂM ĐÃ SỬA SO VỚI BẢN CŨ
   1. Không còn giả định mã đơn liên tục (@Dau + n). IDENTITY có thể nhảy
      số (khởi động lại SQL Server, đơn bị xóa...). Giờ đọc mã đơn thật
      vừa chèn rồi ánh xạ bằng bảng #Map.
   2. Batch B nằm trong một giao dịch: lỗi giữa chừng thì hoàn tác sạch,
      không để lại dữ liệu dở dang làm chặn việc chạy lại.
   3. ABS(CHECKSUM(...) % N) thay cho ABS(CHECKSUM(...)) % N, tránh lỗi
      tràn số hiếm gặp khi CHECKSUM trả đúng giá trị nhỏ nhất của INT.
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

BEGIN TRAN;

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
       (100 + ABS(CHECKSUM(NEWID()) % 29900)) * 1000,
       ABS(CHECKSUM(NEWID()) % 501),
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
       DATEADD(DAY, ABS(CHECKSUM(NEWID()) % 365), '2022-01-01')
FROM #So WHERE n <= @SoKH;

SELECT ROW_NUMBER() OVER (ORDER BY MaKH) AS stt, MaKH
INTO #KH FROM KhachHang WHERE Email LIKE N'kh%@demo.vn';

-- 4. Đơn hàng: ngày 2023-01-01 .. 2026-11-06; 5% ChoXuLy, 15% DaHuy, 80% HoanThanh
SELECT s.n,
       kh.MaKH,
       DATEADD(MINUTE, ABS(CHECKSUM(NEWID()) % (1405 * 1440)), CAST('2023-01-01' AS DATETIME2)) AS NgayDat,
       CASE WHEN r.p < 5 THEN N'ChoXuLy' WHEN r.p < 20 THEN N'DaHuy' ELSE N'HoanThanh' END AS TrangThai,
       1 + ABS(CHECKSUM(NEWID()) % 3) AS SoDong,
       1 + ABS(CHECKSUM(NEWID()) % @SoSP) AS Goc,
       1 + ABS(CHECKSUM(NEWID()) % ((@SoSP - 1) / 2)) AS Buoc
INTO #Don
FROM #So s
CROSS APPLY (SELECT ABS(CHECKSUM(NEWID()) % 100) AS p) r
JOIN #KH kh ON kh.stt = 1 + ABS(CHECKSUM(s.n * 7919) % @SoKH)
WHERE s.n <= @SoDon;

-- Nhớ mã đơn lớn nhất TRƯỚC khi chèn: mọi đơn mới đều có mã lớn hơn số này
DECLARE @Dau INT = ISNULL((SELECT MAX(MaDon) FROM DonHang), 0);

-- ORDER BY n để IDENTITY cấp mã theo đúng thứ tự n
INSERT DonHang(MaKH, NgayDat, TrangThai)
SELECT MaKH, NgayDat, TrangThai FROM #Don ORDER BY n;

-- Ánh xạ số thứ tự n -> mã đơn THẬT (không đoán bằng @Dau + n)
SELECT ROW_NUMBER() OVER (ORDER BY MaDon) AS n, MaDon
INTO #Map
FROM DonHang
WHERE MaDon > @Dau;

IF (SELECT COUNT(*) FROM #Map) <> (SELECT COUNT(*) FROM #Don)
    THROW 50101, N'Số đơn vừa chèn không khớp số đơn dự kiến.', 1;

-- 5. Chi tiết đơn: 1-3 dòng/đơn, sản phẩm khác nhau trong cùng đơn
INSERT ChiTietDonHang(MaDon, MaSP, SoLuong, DonGia)
SELECT m.MaDon, sp.MaSP, 1 + ABS(CHECKSUM(NEWID()) % 5), sp.Gia
FROM #Don d
JOIN #Map m ON m.n = d.n
CROSS JOIN (VALUES (0),(1),(2)) k(k)
JOIN #SP sp ON sp.stt = ((d.Goc - 1 + k.k * d.Buoc) % @SoSP) + 1
WHERE k.k < d.SoDong;

COMMIT;

UPDATE STATISTICS DonHang; UPDATE STATISTICS ChiTietDonHang;
UPDATE STATISTICS SanPham; UPDATE STATISTICS KhachHang;

-- Tóm tắt
SELECT (SELECT COUNT(*) FROM DanhMuc)        AS DanhMuc,
       (SELECT COUNT(*) FROM SanPham)        AS SanPham,
       (SELECT COUNT(*) FROM KhachHang)      AS KhachHang,
       (SELECT COUNT(*) FROM DonHang)        AS DonHang,
       (SELECT COUNT(*) FROM ChiTietDonHang) AS ChiTietDonHang,
       -- Phải bằng 0: mọi đơn vừa nạp đều có ít nhất 1 dòng chi tiết
       (SELECT COUNT(*) FROM DonHang dh
         WHERE dh.MaDon > @Dau
           AND NOT EXISTS (SELECT 1 FROM ChiTietDonHang ct WHERE ct.MaDon = dh.MaDon)) AS DonKhongChiTiet;
GO

/* ===== C. Bật lại trigger (LUÔN chạy, kể cả khi B báo lỗi) ===== */
ENABLE TRIGGER trg_DonHang_NhatKy     ON DonHang;
ENABLE TRIGGER trg_SanPham_LichSuGia  ON SanPham;
ENABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;

SELECT name, is_disabled FROM sys.triggers WHERE parent_class = 1;  -- cả 4 phải = 0
GO

/* ===== D. (CHỈ KHI CẦN) Dọn dữ liệu demo để nạp lại từ đầu =============
   Dùng khi bản cũ đã chạy dở (có khách demo nhưng thiếu chi tiết đơn).
   Bỏ comment, chạy từng batch theo thứ tự D1 -> D2 -> C (bật lại trigger).
   Chỉ xóa dữ liệu demo (email kh...@demo.vn, tên "SP demo", "Danh mục demo"),
   không đụng tới dữ liệu test của bạn.

-- D1
DISABLE TRIGGER trg_DonHang_NhatKy ON DonHang;
GO
-- D2
SET XACT_ABORT ON;
BEGIN TRAN;
DELETE ct FROM ChiTietDonHang ct
  JOIN DonHang dh ON dh.MaDon = ct.MaDon
  JOIN KhachHang kh ON kh.MaKH = dh.MaKH
  WHERE kh.Email LIKE N'kh%@demo.vn';
DELETE dh FROM DonHang dh
  JOIN KhachHang kh ON kh.MaKH = dh.MaKH
  WHERE kh.Email LIKE N'kh%@demo.vn';
DELETE pn FROM KhachHang_PhanNhom pn
  JOIN KhachHang kh ON kh.MaKH = pn.MaKH
  WHERE kh.Email LIKE N'kh%@demo.vn';
DELETE FROM KhachHang WHERE Email LIKE N'kh%@demo.vn';
DELETE FROM SanPham   WHERE TenSP LIKE N'SP demo %';
DELETE FROM DanhMuc   WHERE TenDanhMuc LIKE N'Danh mục demo %';
COMMIT;
GO
-- Sau đó chạy lại batch C để bật trigger, rồi chạy lại A -> B -> C.
   ===================================================================== */