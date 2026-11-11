/* =====================================================================
   03_trigger.sql
   4 trigger của ShopDB. Chạy sau 01_tao_bang.sql và 02_procedure.sql.
   Người viết: Vinh

   QUY TẮC CHUNG
   - Trigger chạy theo cả nhóm dòng (một lệnh UPDATE/DELETE có thể đụng
     nhiều dòng), nên luôn JOIN với inserted / deleted, không gán vào biến.
   - SET NOCOUNT ON để trigger không làm sai số dòng mà procedure đọc
     bằng @@ROWCOUNT (ví dụ trong sp_DatHang).

   LƯU Ý KHI NẠP DỮ LIỆU LỚN (cho Lợi)
   trg_DonHang_NhatKy ghi một dòng NhatKy cho MỖI đơn hàng thêm vào.
   Nạp vài trăm nghìn đơn sẽ sinh ngần ấy dòng nhật ký, chậm và làm bảng
   NhatKy phình to. Trước khi nạp, tắt trigger; nạp xong thì bật lại:
       DISABLE TRIGGER trg_DonHang_NhatKy  ON DonHang;
       DISABLE TRIGGER trg_SanPham_LichSuGia  ON SanPham;
       DISABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;
       -- ... nạp dữ liệu ...
       ENABLE  TRIGGER trg_DonHang_NhatKy  ON DonHang;
       ENABLE  TRIGGER trg_SanPham_LichSuGia  ON SanPham;
       ENABLE  TRIGGER trg_SanPham_CanhBaoKho ON SanPham;
   ===================================================================== */

-- Trigger cũng ghi nhớ QUOTED_IDENTIFIER lúc tạo (xem ghi chú ở 02_procedure.sql).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE ShopDB;
GO

/* ---------------------------------------------------------------------
   1. trg_SanPham_ChanXoa  (INSTEAD OF DELETE)
   - Sản phẩm đã có trong đơn hàng nào: không xóa, chỉ ẩn (DaXoa = 1)
     để các đơn cũ vẫn còn đủ thông tin.
   - Sản phẩm chưa có đơn: xóa thật. Phải xóa dòng ở SanPham_Embedding
     trước, vì bảng đó có khóa ngoại tới SanPham.
   Lệnh DELETE trong trigger này không kích hoạt lại chính nó.
   Tìm sản phẩm trong ChiTietDonHang sẽ nhanh khi có IX_CTDH_MaSP
   (04_index.sql); thiếu index này thì xóa sản phẩm trên dữ liệu lớn sẽ chậm.
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER trg_SanPham_ChanXoa ON SanPham
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Đã có đơn: chỉ ẩn
    UPDATE sp SET DaXoa = 1
    FROM SanPham sp
    JOIN deleted d ON d.MaSP = sp.MaSP
    WHERE EXISTS (SELECT 1 FROM ChiTietDonHang ct WHERE ct.MaSP = d.MaSP);

    -- Chưa có đơn: xóa embedding trước rồi xóa thật
    DELETE e
    FROM SanPham_Embedding e
    JOIN deleted d ON d.MaSP = e.MaSP
    WHERE NOT EXISTS (SELECT 1 FROM ChiTietDonHang ct WHERE ct.MaSP = d.MaSP);

    DELETE sp
    FROM SanPham sp
    JOIN deleted d ON d.MaSP = sp.MaSP
    WHERE NOT EXISTS (SELECT 1 FROM ChiTietDonHang ct WHERE ct.MaSP = d.MaSP);
END
GO

/* ---------------------------------------------------------------------
   2. trg_SanPham_LichSuGia  (AFTER UPDATE)
   Khi giá đổi thì ghi giá cũ và giá mới vào LichSuGia.
   Chỉ ghi những dòng giá thật sự khác (UPDATE đặt lại đúng giá cũ
   thì không ghi).
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER trg_SanPham_LichSuGia ON SanPham
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Gia) RETURN;

    INSERT LichSuGia(MaSP, GiaCu, GiaMoi)
    SELECT i.MaSP, d.Gia, i.Gia
    FROM inserted i
    JOIN deleted d ON d.MaSP = i.MaSP
    WHERE i.Gia <> d.Gia;
END
GO

/* ---------------------------------------------------------------------
   3. trg_DonHang_NhatKy  (AFTER INSERT, UPDATE, DELETE)
   Ghi mọi thao tác thêm, sửa, xóa đơn hàng vào NhatKy.
   Phân biệt thao tác bằng cách ghép inserted và deleted:
     chỉ có ở inserted -> Them
     có ở cả hai       -> Sua
     chỉ có ở deleted  -> Xoa
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER trg_DonHang_NhatKy ON DonHang
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT NhatKy(Bang, ThaoTac, NoiDung)
    SELECT N'DonHang',
           CASE WHEN d.MaDon IS NULL THEN N'Them'
                WHEN i.MaDon IS NULL THEN N'Xoa'
                ELSE N'Sua' END,
           CASE
               WHEN d.MaDon IS NULL THEN
                    N'Thêm đơn ' + CAST(i.MaDon AS NVARCHAR(20))
                  + N' của khách ' + CAST(i.MaKH AS NVARCHAR(20))
                  + N', trạng thái ' + i.TrangThai
               WHEN i.MaDon IS NULL THEN
                    N'Xóa đơn ' + CAST(d.MaDon AS NVARCHAR(20))
                  + N' của khách ' + CAST(d.MaKH AS NVARCHAR(20))
                  + N', trạng thái ' + d.TrangThai
               WHEN d.TrangThai <> i.TrangThai THEN
                    N'Sửa đơn ' + CAST(i.MaDon AS NVARCHAR(20))
                  + N': trạng thái ' + d.TrangThai + N' -> ' + i.TrangThai
               ELSE
                    N'Sửa thông tin đơn ' + CAST(i.MaDon AS NVARCHAR(20))
           END
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.MaDon = i.MaDon;
END
GO

/* ---------------------------------------------------------------------
   4. trg_SanPham_CanhBaoKho  (AFTER UPDATE)
   Ghi cảnh báo khi tồn kho VỪA xuống dưới 5: trước đó >= 5, sau đó < 5.
   Sản phẩm đã dưới 5 từ trước mà tiếp tục giảm thì không ghi lại,
   để nhật ký không bị lặp.
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER trg_SanPham_CanhBaoKho ON SanPham
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(TonKho) RETURN;

    INSERT NhatKy(Bang, ThaoTac, NoiDung)
    SELECT N'SanPham', N'CanhBaoKho',
           N'Sản phẩm ' + CAST(i.MaSP AS NVARCHAR(20))
         + N' (' + i.TenSP + N') chỉ còn '
         + CAST(i.TonKho AS NVARCHAR(20)) + N' cái'
    FROM inserted i
    JOIN deleted d ON d.MaSP = i.MaSP
    WHERE d.TonKho >= 5 AND i.TonKho < 5;
END
GO

/* Kiểm tra: phải thấy đủ 4 trigger */
SELECT name, OBJECT_NAME(parent_id) AS bang, is_instead_of_trigger
FROM sys.triggers
WHERE parent_class = 1
ORDER BY name;
GO

