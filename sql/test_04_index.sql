/* =====================================================================
   test_04_index.sql
   Đo hiệu năng 4 truy vấn. Dùng cho CẢ HAI lần: trước và sau 04_index.sql.
   CÁCH ĐO
   - Ctrl+M bật Actual Execution Plan.
   - Mỗi truy vấn chạy 3 lần, lấy trung bình; ghi logical reads + elapsed time,
     chụp plan. Xem Messages để lấy số liệu.
   - Mỗi lần đo chạy lệnh xóa cache ở mục 1 để công bằng.
   ===================================================================== */
USE ShopDB;
SELECT name FROM sys.indexes WHERE name LIKE N'IX[_]%';
USE ShopDB;
GO

/* ===== 0. Kiểm tra tham số có dữ liệu ============================== */
SELECT (SELECT COUNT(*) FROM DonHang WHERE MaKH = 123
          AND NgayDat >= '2025-01-01' AND NgayDat < '2026-01-01') AS Q1_SoDon,
       (SELECT COUNT(*) FROM ChiTietDonHang WHERE MaSP = 50)      AS Q2_SoDong,
       (SELECT COUNT(*) FROM SanPham WHERE MaDanhMuc = 14
          AND Gia BETWEEN 1000000 AND 5000000)                    AS Q3_SoSP,
       (SELECT COUNT(*) FROM DonHang WHERE TrangThai = N'ChoXuLy') AS Q4_SoDonCho;
-- Nếu Q1/Q2/Q3 = 0: đổi 123, 50, 3 sang giá trị có dữ liệu
-- (vd: MaKH, MaSP, MaDanhMuc lấy từ các dòng "demo").
GO

USE ShopDB;
GO
SELECT TOP 3 dm.MaDanhMuc, dm.TenDanhMuc, COUNT(*) AS SoSP
FROM SanPham sp JOIN DanhMuc dm ON dm.MaDanhMuc = sp.MaDanhMuc
WHERE sp.Gia BETWEEN 1000000 AND 5000000
GROUP BY dm.MaDanhMuc, dm.TenDanhMuc
ORDER BY SoSP DESC;
GO


/* ===== 1. Xóa cache (chạy trước MỖI lần đo) ======================== */
CHECKPOINT; DBCC DROPCLEANBUFFERS;
GO

/* ===== Q1. Đơn của một khách trong một năm ========================= */
SET STATISTICS IO, TIME ON;
SELECT MaDon, NgayDat, TrangThai FROM DonHang
WHERE MaKH = 123 AND NgayDat >= '2025-01-01' AND NgayDat < '2026-01-01';
SET STATISTICS IO, TIME OFF;
GO

/* ===== Q2. Doanh thu của một sản phẩm ============================== */
SET STATISTICS IO, TIME ON;
SELECT SUM(SoLuong * DonGia) FROM ChiTietDonHang WHERE MaSP = 50;
SET STATISTICS IO, TIME OFF;
GO

/* ===== Q3. Sản phẩm theo danh mục và khoảng giá ==================== */
CHECKPOINT; DBCC DROPCLEANBUFFERS;
GO

SET STATISTICS IO, TIME ON;
SELECT MaSP, TenSP, Gia FROM SanPham
WHERE MaDanhMuc = 14 AND Gia BETWEEN 1000000 AND 5000000;
SET STATISTICS IO, TIME OFF;
GO

/* ===== Q4. Đơn chờ xử lý gần đây (giữ nguyên N'ChoXuLy', không dùng tham số) */
CHECKPOINT; DBCC DROPCLEANBUFFERS;
GO
SET STATISTICS IO, TIME ON;
SELECT TOP 50 MaDon, NgayDat FROM DonHang
WHERE TrangThai = N'ChoXuLy' ORDER BY NgayDat DESC;
SET STATISTICS IO, TIME OFF;
GO
