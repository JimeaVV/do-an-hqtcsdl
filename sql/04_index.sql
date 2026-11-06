/* =====================================================================
   04_index.sql
   4 index của ShopDB. Chỉ chạy SAU KHI đã đo "trước" (xem test_04_index.sql).
   Có kiểm tra tồn tại nên chạy lại không lỗi.
   ===================================================================== */
USE ShopDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_DonHang_KH_Ngay' AND object_id = OBJECT_ID(N'DonHang'))
    CREATE INDEX IX_DonHang_KH_Ngay ON DonHang(MaKH, NgayDat) INCLUDE (TrangThai);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CTDH_MaSP' AND object_id = OBJECT_ID(N'ChiTietDonHang'))
    CREATE INDEX IX_CTDH_MaSP ON ChiTietDonHang(MaSP) INCLUDE (SoLuong, DonGia);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_SanPham_DM_Gia' AND object_id = OBJECT_ID(N'SanPham'))
    CREATE INDEX IX_SanPham_DM_Gia ON SanPham(MaDanhMuc, Gia);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_DonHang_ChoXuLy' AND object_id = OBJECT_ID(N'DonHang'))
    CREATE INDEX IX_DonHang_ChoXuLy ON DonHang(NgayDat) WHERE TrangThai = N'ChoXuLy';
GO

SELECT OBJECT_NAME(object_id) AS bang, name FROM sys.indexes WHERE name LIKE N'IX[_]%' ORDER BY name;
GO

/* Muốn đo lại "trước" thì xóa 4 index:
DROP INDEX IX_DonHang_KH_Ngay   ON DonHang;
DROP INDEX IX_CTDH_MaSP         ON ChiTietDonHang;
DROP INDEX IX_SanPham_DM_Gia    ON SanPham;
DROP INDEX IX_DonHang_ChoXuLy   ON DonHang;
*/
