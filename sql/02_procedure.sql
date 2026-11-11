/* =====================================================================
   02_procedure.sql
   Toàn bộ stored procedure của ShopDB. Chạy sau 01_tao_bang.sql.
   Người viết: Vinh

   QUY ƯỚC CHUNG
   - Tên: sp_Bang_ThaoTac.
   - Procedure đọc danh sách có phân trang: @Trang (từ 1), @KichThuoc
     (mặc định 20, tối đa 200). Cột TongSo trong kết quả là tổng số dòng
     thỏa điều kiện, để web tính số trang.
   - Mã lỗi nghiệp vụ (THROW):
       50001  Không đủ hàng
       50002  Đối tượng không tồn tại (sản phẩm, danh mục, khách, đơn)
       50003  Danh mục còn sản phẩm, không xóa được
       50004  Email đã tồn tại
       50005  Khách hàng đã có đơn hàng, không xóa được
       50006  Đơn không tồn tại hoặc không ở trạng thái ChoXuLy
       50007  Dữ liệu JSON không hợp lệ
       50008  Tên danh mục đã tồn tại
   - Procedure thêm trả mã mới qua tham số OUTPUT.

   VỀ SET QUOTED_IDENTIFIER
   Mỗi procedure ghi nhớ giá trị QUOTED_IDENTIFIER tại lúc được tạo. Bảng
   DonHang có filtered index (04_index.sql) nên mọi lệnh INSERT/UPDATE/DELETE
   vào nó phải chạy với QUOTED_IDENTIFIER ON. sqlcmd mặc định là OFF (trừ khi
   có -I), nên hai dòng SET dưới đây đảm bảo procedure luôn được tạo đúng
   dù chạy file bằng SSMS hay sqlcmd.
   ===================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE ShopDB;
GO

/* =====================================================================
   A. DANH MỤC
   ===================================================================== */

CREATE OR ALTER PROC sp_DanhMuc_Them
    @TenDanhMuc NVARCHAR(100),
    @MaDanhMuc  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM DanhMuc WHERE TenDanhMuc = @TenDanhMuc)
        THROW 50008, N'Tên danh mục đã tồn tại', 1;

    INSERT DanhMuc(TenDanhMuc) VALUES (@TenDanhMuc);
    SET @MaDanhMuc = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROC sp_DanhMuc_Sua
    @MaDanhMuc  INT,
    @TenDanhMuc NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM DanhMuc WHERE MaDanhMuc = @MaDanhMuc)
        THROW 50002, N'Danh mục không tồn tại', 1;
    IF EXISTS (SELECT 1 FROM DanhMuc WHERE TenDanhMuc = @TenDanhMuc AND MaDanhMuc <> @MaDanhMuc)
        THROW 50008, N'Tên danh mục đã tồn tại', 1;

    UPDATE DanhMuc SET TenDanhMuc = @TenDanhMuc WHERE MaDanhMuc = @MaDanhMuc;
END
GO

CREATE OR ALTER PROC sp_DanhMuc_Xoa
    @MaDanhMuc INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM DanhMuc WHERE MaDanhMuc = @MaDanhMuc)
        THROW 50002, N'Danh mục không tồn tại', 1;
    IF EXISTS (SELECT 1 FROM SanPham WHERE MaDanhMuc = @MaDanhMuc)
        THROW 50003, N'Danh mục còn sản phẩm, không thể xóa', 1;

    DELETE DanhMuc WHERE MaDanhMuc = @MaDanhMuc;
END
GO

CREATE OR ALTER PROC sp_DanhMuc_LayDS
    @TuKhoa    NVARCHAR(100) = NULL,
    @Trang     INT = 1,
    @KichThuoc INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @Trang < 1 SET @Trang = 1;
    IF @KichThuoc < 1 SET @KichThuoc = 20;
    IF @KichThuoc > 200 SET @KichThuoc = 200;

    SELECT dm.MaDanhMuc,
           dm.TenDanhMuc,
           (SELECT COUNT(*) FROM SanPham sp
             WHERE sp.MaDanhMuc = dm.MaDanhMuc AND sp.DaXoa = 0) AS SoSanPham,
           COUNT(*) OVER () AS TongSo
    FROM DanhMuc dm
    WHERE @TuKhoa IS NULL OR dm.TenDanhMuc LIKE N'%' + @TuKhoa + N'%'
    ORDER BY dm.MaDanhMuc
    OFFSET (@Trang - 1) * @KichThuoc ROWS FETCH NEXT @KichThuoc ROWS ONLY;
END
GO

/* =====================================================================
   B. SẢN PHẨM
   ===================================================================== */

CREATE OR ALTER PROC sp_SanPham_Them
    @MaDanhMuc INT,
    @TenSP     NVARCHAR(200),
    @MoTa      NVARCHAR(MAX) = NULL,
    @Gia       DECIMAL(18,0),
    @TonKho    INT = 0,
    @MaSP      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM DanhMuc WHERE MaDanhMuc = @MaDanhMuc)
        THROW 50002, N'Danh mục không tồn tại', 1;

    INSERT SanPham(MaDanhMuc, TenSP, MoTa, Gia, TonKho)
    VALUES (@MaDanhMuc, @TenSP, @MoTa, @Gia, @TonKho);
    SET @MaSP = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROC sp_SanPham_Sua
    @MaSP      INT,
    @MaDanhMuc INT,
    @TenSP     NVARCHAR(200),
    @MoTa      NVARCHAR(MAX) = NULL,
    @Gia       DECIMAL(18,0),
    @TonKho    INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM SanPham WHERE MaSP = @MaSP)
        THROW 50002, N'Sản phẩm không tồn tại', 1;
    IF NOT EXISTS (SELECT 1 FROM DanhMuc WHERE MaDanhMuc = @MaDanhMuc)
        THROW 50002, N'Danh mục không tồn tại', 1;

    UPDATE SanPham
    SET MaDanhMuc = @MaDanhMuc, TenSP = @TenSP, MoTa = @MoTa,
        Gia = @Gia, TonKho = @TonKho
    WHERE MaSP = @MaSP;
END
GO

/* Xóa: thực chất là DELETE, trigger trg_SanPham_ChanXoa (03_trigger.sql)
   quyết định xóa thật hay ẩn. Sau đó kiểm tra lại để báo đúng cho web:
   DaXoa = đã xóa thật, DaAn = chỉ bị ẩn vì đã có đơn hàng. */
CREATE OR ALTER PROC sp_SanPham_Xoa
    @MaSP INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM SanPham WHERE MaSP = @MaSP)
        THROW 50002, N'Sản phẩm không tồn tại', 1;

    DELETE FROM SanPham WHERE MaSP = @MaSP;

    IF EXISTS (SELECT 1 FROM SanPham WHERE MaSP = @MaSP)
    BEGIN
        SELECT N'DaAn' AS KetQua;
    END
    ELSE
    BEGIN
        SELECT N'DaXoa' AS KetQua;
    END
END
GO

/* Chỉ trả sản phẩm chưa bị ẩn. Lọc theo từ khóa trong tên và/hoặc danh mục.
   OPTION (RECOMPILE): để các tham số NULL không làm optimizer bỏ qua index. */
CREATE OR ALTER PROC sp_SanPham_LayDS
    @TuKhoa    NVARCHAR(100) = NULL,
    @MaDanhMuc INT = NULL,
    @Trang     INT = 1,
    @KichThuoc INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @Trang < 1 SET @Trang = 1;
    IF @KichThuoc < 1 SET @KichThuoc = 20;
    IF @KichThuoc > 200 SET @KichThuoc = 200;

    SELECT sp.MaSP, sp.MaDanhMuc, dm.TenDanhMuc, sp.TenSP, sp.MoTa,
           sp.Gia, sp.TonKho,
           COUNT(*) OVER () AS TongSo
    FROM SanPham sp
    JOIN DanhMuc dm ON dm.MaDanhMuc = sp.MaDanhMuc
    WHERE sp.DaXoa = 0
      AND (@MaDanhMuc IS NULL OR sp.MaDanhMuc = @MaDanhMuc)
      AND (@TuKhoa IS NULL OR sp.TenSP LIKE N'%' + @TuKhoa + N'%')
    ORDER BY sp.MaSP DESC
    OFFSET (@Trang - 1) * @KichThuoc ROWS FETCH NEXT @KichThuoc ROWS ONLY
    OPTION (RECOMPILE);
END
GO

CREATE OR ALTER PROC sp_SanPham_LayTheoMa
    @MaSP INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT sp.MaSP, sp.MaDanhMuc, dm.TenDanhMuc, sp.TenSP, sp.MoTa,
           sp.Gia, sp.TonKho
    FROM SanPham sp
    JOIN DanhMuc dm ON dm.MaDanhMuc = sp.MaDanhMuc
    WHERE sp.MaSP = @MaSP AND sp.DaXoa = 0;
END
GO

/* =====================================================================
   C. KHÁCH HÀNG
   ===================================================================== */

CREATE OR ALTER PROC sp_KhachHang_Them
    @HoTen NVARCHAR(100),
    @Email NVARCHAR(150),
    @SDT   VARCHAR(20) = NULL,
    @MaKH  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM KhachHang WHERE Email = @Email)
        THROW 50004, N'Email đã tồn tại', 1;

    INSERT KhachHang(HoTen, Email, SDT) VALUES (@HoTen, @Email, @SDT);
    SET @MaKH = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROC sp_KhachHang_Sua
    @MaKH  INT,
    @HoTen NVARCHAR(100),
    @Email NVARCHAR(150),
    @SDT   VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE MaKH = @MaKH)
        THROW 50002, N'Khách hàng không tồn tại', 1;
    IF EXISTS (SELECT 1 FROM KhachHang WHERE Email = @Email AND MaKH <> @MaKH)
        THROW 50004, N'Email đã tồn tại', 1;

    UPDATE KhachHang SET HoTen = @HoTen, Email = @Email, SDT = @SDT
    WHERE MaKH = @MaKH;
END
GO

/* Khách đã có đơn thì không xóa (giữ lịch sử đơn hàng). */
CREATE OR ALTER PROC sp_KhachHang_Xoa
    @MaKH INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE MaKH = @MaKH)
            THROW 50002, N'Khách hàng không tồn tại', 1;
        IF EXISTS (SELECT 1 FROM DonHang WHERE MaKH = @MaKH)
            THROW 50005, N'Khách hàng đã có đơn hàng, không thể xóa', 1;

        BEGIN TRAN;
        DELETE KhachHang_PhanNhom WHERE MaKH = @MaKH;
        DELETE KhachHang WHERE MaKH = @MaKH;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROC sp_KhachHang_LayDS
    @TuKhoa    NVARCHAR(100) = NULL,
    @Trang     INT = 1,
    @KichThuoc INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @Trang < 1 SET @Trang = 1;
    IF @KichThuoc < 1 SET @KichThuoc = 20;
    IF @KichThuoc > 200 SET @KichThuoc = 200;

    SELECT kh.MaKH, kh.HoTen, kh.Email, kh.SDT, kh.NgayTao,
           COUNT(*) OVER () AS TongSo
    FROM KhachHang kh
    WHERE @TuKhoa IS NULL
       OR kh.HoTen LIKE N'%' + @TuKhoa + N'%'
       OR kh.Email LIKE N'%' + @TuKhoa + N'%'
       OR kh.SDT   LIKE N'%' + @TuKhoa + N'%'
    ORDER BY kh.MaKH DESC
    OFFSET (@Trang - 1) * @KichThuoc ROWS FETCH NEXT @KichThuoc ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* =====================================================================
   D. GIAO DỊCH
   ===================================================================== */

/* Đặt hàng. @GioHang là JSON: [{"MaSP":1,"SoLuong":2},{"MaSP":5,"SoLuong":1}]
   - Gộp các dòng trùng MaSP.
   - Chỉ trừ kho khi còn đủ hàng; thiếu một món là hủy cả đơn (ROLLBACK).
   - DonGia lưu giá tại thời điểm mua. */
CREATE OR ALTER PROC sp_DatHang
    @MaKH    INT,
    @GioHang NVARCHAR(MAX),
    @MaDon   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Hang TABLE (MaSP INT PRIMARY KEY, SoLuong INT NOT NULL);
    DECLARE @SoDong INT;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE MaKH = @MaKH)
            THROW 50002, N'Khách hàng không tồn tại', 1;

        IF ISNULL(ISJSON(@GioHang), 0) <> 1
           OR NOT EXISTS (SELECT 1 FROM OPENJSON(@GioHang))
           OR EXISTS (SELECT 1
                      FROM OPENJSON(@GioHang)
                           WITH (MaSP INT '$.MaSP', SoLuong INT '$.SoLuong')
                      WHERE MaSP IS NULL OR SoLuong IS NULL OR SoLuong <= 0)
            THROW 50007, N'Giỏ hàng không hợp lệ', 1;

        BEGIN TRAN;

        INSERT @Hang(MaSP, SoLuong)
        SELECT MaSP, SUM(SoLuong)
        FROM OPENJSON(@GioHang) WITH (MaSP INT '$.MaSP', SoLuong INT '$.SoLuong')
        GROUP BY MaSP;

        -- Chỉ trừ kho khi còn đủ hàng
        UPDATE sp SET TonKho = sp.TonKho - h.SoLuong
        FROM SanPham sp JOIN @Hang h ON h.MaSP = sp.MaSP
        WHERE sp.TonKho >= h.SoLuong AND sp.DaXoa = 0;

        SET @SoDong = @@ROWCOUNT;
        IF @SoDong <> (SELECT COUNT(*) FROM @Hang)
            THROW 50001, N'Không đủ hàng', 1;

        INSERT DonHang(MaKH, NgayDat, TrangThai)
        VALUES (@MaKH, SYSDATETIME(), N'ChoXuLy');
        SET @MaDon = SCOPE_IDENTITY();

        INSERT ChiTietDonHang(MaDon, MaSP, SoLuong, DonGia)
        SELECT @MaDon, h.MaSP, h.SoLuong, sp.Gia
        FROM @Hang h JOIN SanPham sp ON sp.MaSP = h.MaSP;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* Hủy đơn: chỉ đơn đang ChoXuLy. Đổi sang DaHuy và cộng lại tồn kho.
   UPDATE có điều kiện TrangThai nên hai người cùng hủy một đơn
   thì chỉ một người thành công, kho không bị cộng hai lần. */
CREATE OR ALTER PROC sp_HuyDon
    @MaDon INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        UPDATE DonHang SET TrangThai = N'DaHuy'
        WHERE MaDon = @MaDon AND TrangThai = N'ChoXuLy';

        IF @@ROWCOUNT = 0
            THROW 50006, N'Đơn không tồn tại hoặc không ở trạng thái chờ xử lý', 1;

        UPDATE sp SET TonKho = sp.TonKho + ct.SoLuong
        FROM SanPham sp JOIN ChiTietDonHang ct ON ct.MaSP = sp.MaSP
        WHERE ct.MaDon = @MaDon;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* Thanh toán: đổi đơn ChoXuLy thành HoanThanh và ghi ThanhToan.
   Số tiền do database tự tính từ chi tiết đơn, không tin số web gửi lên. */
CREATE OR ALTER PROC sp_ThanhToan
    @MaDon      INT,
    @PhuongThuc NVARCHAR(50),
    @MaTT       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @SoTien DECIMAL(18,0);

    BEGIN TRY
        BEGIN TRAN;

        UPDATE DonHang SET TrangThai = N'HoanThanh'
        WHERE MaDon = @MaDon AND TrangThai = N'ChoXuLy';

        IF @@ROWCOUNT = 0
            THROW 50006, N'Đơn không tồn tại hoặc không ở trạng thái chờ xử lý', 1;

        SELECT @SoTien = ISNULL(SUM(SoLuong * DonGia), 0)
        FROM ChiTietDonHang WHERE MaDon = @MaDon;

        INSERT ThanhToan(MaDon, SoTien, NgayTT, PhuongThuc)
        VALUES (@MaDon, @SoTien, SYSDATETIME(), @PhuongThuc);
        SET @MaTT = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   E. ĐƠN HÀNG
   ===================================================================== */

/* Phân trang trước rồi mới tính tổng tiền, để chỉ tính cho đúng 1 trang. */
CREATE OR ALTER PROC sp_DonHang_LayDS
    @MaKH      INT = NULL,
    @TrangThai NVARCHAR(20) = NULL,
    @Trang     INT = 1,
    @KichThuoc INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @Trang < 1 SET @Trang = 1;
    IF @KichThuoc < 1 SET @KichThuoc = 20;
    IF @KichThuoc > 200 SET @KichThuoc = 200;

    WITH D AS (
        SELECT dh.MaDon, dh.MaKH, dh.NgayDat, dh.TrangThai,
               COUNT(*) OVER () AS TongSo
        FROM DonHang dh
        WHERE (@MaKH IS NULL OR dh.MaKH = @MaKH)
          AND (@TrangThai IS NULL OR dh.TrangThai = @TrangThai)
        ORDER BY dh.NgayDat DESC, dh.MaDon DESC
        OFFSET (@Trang - 1) * @KichThuoc ROWS FETCH NEXT @KichThuoc ROWS ONLY
    )
    SELECT D.MaDon, D.MaKH, kh.HoTen, D.NgayDat, D.TrangThai,
           (SELECT ISNULL(SUM(ct.SoLuong * ct.DonGia), 0)
              FROM ChiTietDonHang ct WHERE ct.MaDon = D.MaDon) AS TongTien,
           D.TongSo
    FROM D
    JOIN KhachHang kh ON kh.MaKH = D.MaKH
    ORDER BY D.NgayDat DESC, D.MaDon DESC
    OPTION (RECOMPILE);
END
GO

/* Trả 2 result set: (1) thông tin đơn, (2) các dòng chi tiết. */
CREATE OR ALTER PROC sp_DonHang_LayChiTiet
    @MaDon INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM DonHang WHERE MaDon = @MaDon)
        THROW 50002, N'Đơn hàng không tồn tại', 1;

    SELECT dh.MaDon, dh.MaKH, kh.HoTen, kh.Email, dh.NgayDat, dh.TrangThai,
           ISNULL(SUM(ct.SoLuong * ct.DonGia), 0) AS TongTien
    FROM DonHang dh
    JOIN KhachHang kh ON kh.MaKH = dh.MaKH
    LEFT JOIN ChiTietDonHang ct ON ct.MaDon = dh.MaDon
    WHERE dh.MaDon = @MaDon
    GROUP BY dh.MaDon, dh.MaKH, kh.HoTen, kh.Email, dh.NgayDat, dh.TrangThai;

    SELECT ct.MaSP, sp.TenSP, ct.SoLuong, ct.DonGia,
           ct.SoLuong * ct.DonGia AS ThanhTien
    FROM ChiTietDonHang ct
    JOIN SanPham sp ON sp.MaSP = ct.MaSP
    WHERE ct.MaDon = @MaDon
    ORDER BY ct.MaSP;
END
GO

/* =====================================================================
   F. THỐNG KÊ
   ===================================================================== */

/* Trả 3 result set:
   (1) các số tổng quan, (2) top 5 sản phẩm bán chạy,
   (3) doanh thu 6 tháng gần nhất. Doanh thu chỉ tính đơn HoanThanh. */
CREATE OR ALTER PROC sp_ThongKe_Dashboard
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (SELECT ISNULL(SUM(ct.SoLuong * ct.DonGia), 0)
           FROM ChiTietDonHang ct JOIN DonHang dh ON dh.MaDon = ct.MaDon
          WHERE dh.TrangThai = N'HoanThanh')                    AS DoanhThu,
        (SELECT COUNT(*) FROM DonHang)                          AS TongDon,
        (SELECT COUNT(*) FROM DonHang WHERE TrangThai = N'ChoXuLy')   AS DonChoXuLy,
        (SELECT COUNT(*) FROM DonHang WHERE TrangThai = N'HoanThanh') AS DonHoanThanh,
        (SELECT COUNT(*) FROM DonHang WHERE TrangThai = N'DaHuy')     AS DonDaHuy,
        (SELECT COUNT(*) FROM KhachHang)                        AS SoKhachHang,
        (SELECT COUNT(*) FROM SanPham WHERE DaXoa = 0)          AS SoSanPham,
        (SELECT COUNT(*) FROM SanPham WHERE DaXoa = 0 AND TonKho < 5) AS SapHetHang;

    SELECT TOP 5 sp.MaSP, sp.TenSP,
           SUM(ct.SoLuong) AS DaBan,
           SUM(ct.SoLuong * ct.DonGia) AS DoanhThu
    FROM ChiTietDonHang ct
    JOIN DonHang dh ON dh.MaDon = ct.MaDon
    JOIN SanPham sp ON sp.MaSP = ct.MaSP
    WHERE dh.TrangThai = N'HoanThanh'
    GROUP BY sp.MaSP, sp.TenSP
    ORDER BY DaBan DESC;

    SELECT YEAR(dh.NgayDat) AS Nam, MONTH(dh.NgayDat) AS Thang,
           SUM(ct.SoLuong * ct.DonGia) AS DoanhThu
    FROM DonHang dh
    JOIN ChiTietDonHang ct ON ct.MaDon = dh.MaDon
    WHERE dh.TrangThai = N'HoanThanh'
      AND dh.NgayDat >= DATEADD(MONTH, -5,
              DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1))
    GROUP BY YEAR(dh.NgayDat), MONTH(dh.NgayDat)
    ORDER BY Nam, Thang;
END
GO

CREATE OR ALTER PROC sp_NhatKy_LayDS
    @Bang      NVARCHAR(50) = NULL,
    @ThaoTac   NVARCHAR(50) = NULL,
    @Trang     INT = 1,
    @KichThuoc INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @Trang < 1 SET @Trang = 1;
    IF @KichThuoc < 1 SET @KichThuoc = 20;
    IF @KichThuoc > 200 SET @KichThuoc = 200;

    SELECT nk.MaNK, nk.Bang, nk.ThaoTac, nk.NoiDung, nk.ThoiGian,
           COUNT(*) OVER () AS TongSo
    FROM NhatKy nk
    WHERE (@Bang IS NULL OR nk.Bang = @Bang)
      AND (@ThaoTac IS NULL OR nk.ThaoTac = @ThaoTac)
    ORDER BY nk.MaNK DESC
    OFFSET (@Trang - 1) * @KichThuoc ROWS FETCH NEXT @KichThuoc ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* Liệt kê procedure, trigger, index do nhóm tạo (từ bảng hệ thống).
   Index của khóa chính và ràng buộc UNIQUE không liệt kê. */
CREATE OR ALTER PROC sp_DoiTuongCSDL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT N'Procedure' AS Loai, p.name AS Ten,
           CAST(NULL AS NVARCHAR(128)) AS Bang, p.create_date AS NgayTao
    FROM sys.procedures p
    UNION ALL
    SELECT N'Trigger', tr.name, OBJECT_NAME(tr.parent_id), tr.create_date
    FROM sys.triggers tr
    WHERE tr.parent_class = 1
    UNION ALL
    SELECT N'Index', i.name, OBJECT_NAME(i.object_id), CAST(NULL AS DATETIME)
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE i.name IS NOT NULL
      AND i.is_primary_key = 0
      AND i.is_unique_constraint = 0
    ORDER BY Loai, Ten;
END
GO

/* =====================================================================
   G. AI (phục vụ Lợi và Giang)
   ===================================================================== */

/* Tính R, F, M cho từng khách từ các đơn HoanThanh rồi ghi vào
   KhachHang_PhanNhom. Cột Nhom do Lợi gán, procedure này không đụng tới.
     R: số ngày từ lần mua gần nhất đến @NgayTinh (càng nhỏ càng tốt)
     F: số đơn hoàn thành
     M: tổng tiền đã chi */
CREATE OR ALTER PROC sp_TinhRFM
    @NgayTinh DATE = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @RFM TABLE (MaKH INT PRIMARY KEY, R INT, F INT, M DECIMAL(18,0));

    BEGIN TRY
        SET @NgayTinh = ISNULL(@NgayTinh, CAST(SYSDATETIME() AS DATE));

        BEGIN TRAN;

        INSERT @RFM(MaKH, R, F, M)
        SELECT dh.MaKH,
               DATEDIFF(DAY, MAX(dh.NgayDat), @NgayTinh),
               COUNT(DISTINCT dh.MaDon),
               SUM(ct.SoLuong * ct.DonGia)
        FROM DonHang dh
        JOIN ChiTietDonHang ct ON ct.MaDon = dh.MaDon
        WHERE dh.TrangThai = N'HoanThanh'
          AND dh.NgayDat < DATEADD(DAY, 1, @NgayTinh)
        GROUP BY dh.MaKH;

        UPDATE pn SET R = r.R, F = r.F, M = r.M
        FROM KhachHang_PhanNhom pn
        JOIN @RFM r ON r.MaKH = pn.MaKH;

        INSERT KhachHang_PhanNhom(MaKH, R, F, M)
        SELECT r.MaKH, r.R, r.F, r.M
        FROM @RFM r
        WHERE NOT EXISTS (SELECT 1 FROM KhachHang_PhanNhom pn WHERE pn.MaKH = r.MaKH);

        COMMIT;

        SELECT COUNT(*) AS SoKhachHangDaTinh FROM @RFM;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* Lấy thông tin sản phẩm theo một danh sách mã (ví dụ kết quả gợi ý của AI).
   @DSMaSP là JSON mảng số: [3,1,7]. Kết quả giữ đúng thứ tự trong danh sách.
   Bỏ qua sản phẩm không tồn tại hoặc đã bị ẩn. */
CREATE OR ALTER PROC sp_SanPham_LayTheoDS
    @DSMaSP NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(ISJSON(@DSMaSP), 0) <> 1
        THROW 50007, N'Danh sách mã sản phẩm không hợp lệ, cần dạng [1,2,3]', 1;

    SELECT sp.MaSP, sp.TenSP, sp.MoTa, sp.Gia, sp.TonKho, dm.TenDanhMuc
    FROM (SELECT TRY_CAST([value] AS INT) AS MaSP,
                 CAST([key] AS INT)       AS ThuTu
          FROM OPENJSON(@DSMaSP)) d
    JOIN SanPham sp ON sp.MaSP = d.MaSP
    JOIN DanhMuc dm ON dm.MaDanhMuc = sp.MaDanhMuc
    WHERE sp.DaXoa = 0
    ORDER BY d.ThuTu;
END
GO

/* Thống kê theo nhóm khách hàng: số khách, R/F/M trung bình, tổng chi tiêu. */
CREATE OR ALTER PROC sp_PhanNhom_ThongKe
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL(Nhom, N'Chưa phân nhóm')        AS Nhom,
           COUNT(*)                               AS SoKhachHang,
           AVG(CAST(R AS DECIMAL(18,2)))          AS R_TrungBinh,
           AVG(CAST(F AS DECIMAL(18,2)))          AS F_TrungBinh,
           CAST(AVG(M) AS DECIMAL(18,0))          AS M_TrungBinh,
           SUM(M)                                 AS TongChiTieu
    FROM KhachHang_PhanNhom
    GROUP BY ISNULL(Nhom, N'Chưa phân nhóm')
    ORDER BY SoKhachHang DESC;
END
GO

/* Kiểm tra: liệt kê các procedure vừa tạo (phải đủ 24). */
SELECT COUNT(*) AS SoProcedure FROM sys.procedures;
SELECT name, create_date FROM sys.procedures ORDER BY name;
GO

