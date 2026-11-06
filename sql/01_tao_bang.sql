/* =====================================================================
   01_tao_bang.sql
   Tạo database ShopDB, các bảng, khóa chính, khóa ngoại, ràng buộc.
   Người viết: Vinh
   Chạy trên SQL Server (SSMS). Chạy nguyên file từ trên xuống dưới.
   ===================================================================== */

IF DB_ID(N'ShopDB') IS NULL
    CREATE DATABASE ShopDB;
GO

USE ShopDB;
GO

/* ---------------------------------------------------------------------
   (Tùy chọn) Xóa bảng cũ để tạo lại từ đầu. Bỏ comment khi cần.
   Thứ tự xóa ngược với thứ tự tạo để không vướng khóa ngoại.
   ---------------------------------------------------------------------
DROP TABLE IF EXISTS KhachHang_PhanNhom;
DROP TABLE IF EXISTS SanPham_Embedding;
DROP TABLE IF EXISTS NhatKy;
DROP TABLE IF EXISTS LichSuGia;
DROP TABLE IF EXISTS ThanhToan;
DROP TABLE IF EXISTS ChiTietDonHang;
DROP TABLE IF EXISTS DonHang;
DROP TABLE IF EXISTS KhachHang;
DROP TABLE IF EXISTS SanPham;
DROP TABLE IF EXISTS DanhMuc;
GO
*/

/* ---------------------------------------------------------------------
   1. DanhMuc
   --------------------------------------------------------------------- */
CREATE TABLE DanhMuc (
    MaDanhMuc  INT IDENTITY(1,1) NOT NULL,
    TenDanhMuc NVARCHAR(100)     NOT NULL,
    CONSTRAINT PK_DanhMuc PRIMARY KEY (MaDanhMuc),
    CONSTRAINT UQ_DanhMuc_Ten UNIQUE (TenDanhMuc)
);
GO

/* ---------------------------------------------------------------------
   2. SanPham
   DaXoa = 1: sản phẩm bị ẩn (đã có đơn hàng nên không xóa thật được).
   --------------------------------------------------------------------- */
CREATE TABLE SanPham (
    MaSP       INT IDENTITY(1,1) NOT NULL,
    MaDanhMuc  INT               NOT NULL,
    TenSP      NVARCHAR(200)     NOT NULL,
    MoTa       NVARCHAR(MAX)     NULL,
    Gia        DECIMAL(18,0)     NOT NULL,
    TonKho     INT               NOT NULL CONSTRAINT DF_SanPham_TonKho DEFAULT 0,
    DaXoa      BIT               NOT NULL CONSTRAINT DF_SanPham_DaXoa  DEFAULT 0,
    CONSTRAINT PK_SanPham PRIMARY KEY (MaSP),
    CONSTRAINT FK_SanPham_DanhMuc FOREIGN KEY (MaDanhMuc) REFERENCES DanhMuc(MaDanhMuc),
    CONSTRAINT CK_SanPham_Gia    CHECK (Gia >= 0),
    CONSTRAINT CK_SanPham_TonKho CHECK (TonKho >= 0)
);
GO

/* ---------------------------------------------------------------------
   3. KhachHang
   --------------------------------------------------------------------- */
CREATE TABLE KhachHang (
    MaKH    INT IDENTITY(1,1) NOT NULL,
    HoTen   NVARCHAR(100)     NOT NULL,
    Email   NVARCHAR(150)     NOT NULL,
    SDT     VARCHAR(20)       NULL,
    NgayTao DATETIME2(0)      NOT NULL CONSTRAINT DF_KhachHang_NgayTao DEFAULT SYSDATETIME(),
    CONSTRAINT PK_KhachHang PRIMARY KEY (MaKH),
    CONSTRAINT UQ_KhachHang_Email UNIQUE (Email)
);
GO

/* ---------------------------------------------------------------------
   4. DonHang
   Trạng thái: ChoXuLy, HoanThanh, DaHuy
   --------------------------------------------------------------------- */
CREATE TABLE DonHang (
    MaDon     INT IDENTITY(1,1) NOT NULL,
    MaKH      INT               NOT NULL,
    NgayDat   DATETIME2(0)      NOT NULL CONSTRAINT DF_DonHang_NgayDat   DEFAULT SYSDATETIME(),
    TrangThai NVARCHAR(20)      NOT NULL CONSTRAINT DF_DonHang_TrangThai DEFAULT N'ChoXuLy',
    CONSTRAINT PK_DonHang PRIMARY KEY (MaDon),
    CONSTRAINT FK_DonHang_KhachHang FOREIGN KEY (MaKH) REFERENCES KhachHang(MaKH),
    CONSTRAINT CK_DonHang_TrangThai CHECK (TrangThai IN (N'ChoXuLy', N'HoanThanh', N'DaHuy'))
);
GO

/* ---------------------------------------------------------------------
   5. ChiTietDonHang
   DonGia là giá lúc mua: đổi giá sản phẩm sau này không làm sai đơn cũ.
   --------------------------------------------------------------------- */
CREATE TABLE ChiTietDonHang (
    MaDon   INT           NOT NULL,
    MaSP    INT           NOT NULL,
    SoLuong INT           NOT NULL,
    DonGia  DECIMAL(18,0) NOT NULL,
    CONSTRAINT PK_ChiTietDonHang PRIMARY KEY (MaDon, MaSP),
    CONSTRAINT FK_CTDH_DonHang FOREIGN KEY (MaDon) REFERENCES DonHang(MaDon),
    CONSTRAINT FK_CTDH_SanPham FOREIGN KEY (MaSP)  REFERENCES SanPham(MaSP),
    CONSTRAINT CK_CTDH_SoLuong CHECK (SoLuong > 0),
    CONSTRAINT CK_CTDH_DonGia  CHECK (DonGia >= 0)
);
GO

/* ---------------------------------------------------------------------
   6. ThanhToan
   --------------------------------------------------------------------- */
CREATE TABLE ThanhToan (
    MaTT       INT IDENTITY(1,1) NOT NULL,
    MaDon      INT               NOT NULL,
    SoTien     DECIMAL(18,0)     NOT NULL,
    NgayTT     DATETIME2(0)      NOT NULL CONSTRAINT DF_ThanhToan_NgayTT DEFAULT SYSDATETIME(),
    PhuongThuc NVARCHAR(50)      NOT NULL,
    CONSTRAINT PK_ThanhToan PRIMARY KEY (MaTT),
    CONSTRAINT FK_ThanhToan_DonHang FOREIGN KEY (MaDon) REFERENCES DonHang(MaDon),
    CONSTRAINT CK_ThanhToan_SoTien CHECK (SoTien >= 0)
);
GO

/* ---------------------------------------------------------------------
   7. LichSuGia (do trigger trg_SanPham_LichSuGia ghi)
   Cố ý KHÔNG tạo khóa ngoại tới SanPham: đây là bảng lịch sử, và nếu có
   khóa ngoại thì không xóa thật được sản phẩm chưa có đơn.
   --------------------------------------------------------------------- */
CREATE TABLE LichSuGia (
    MaLS    INT IDENTITY(1,1) NOT NULL,
    MaSP    INT               NOT NULL,
    GiaCu   DECIMAL(18,0)     NOT NULL,
    GiaMoi  DECIMAL(18,0)     NOT NULL,
    NgayDoi DATETIME2(0)      NOT NULL CONSTRAINT DF_LichSuGia_NgayDoi DEFAULT SYSDATETIME(),
    CONSTRAINT PK_LichSuGia PRIMARY KEY (MaLS)
);
GO

/* ---------------------------------------------------------------------
   8. NhatKy (do trigger ghi)
   Bảng nhật ký, cũng không có khóa ngoại.
   --------------------------------------------------------------------- */
CREATE TABLE NhatKy (
    MaNK     INT IDENTITY(1,1) NOT NULL,
    Bang     NVARCHAR(50)      NOT NULL,
    ThaoTac  NVARCHAR(50)      NOT NULL,
    NoiDung  NVARCHAR(500)     NULL,
    ThoiGian DATETIME2(0)      NOT NULL CONSTRAINT DF_NhatKy_ThoiGian DEFAULT SYSDATETIME(),
    CONSTRAINT PK_NhatKy PRIMARY KEY (MaNK)
);
GO

/* ---------------------------------------------------------------------
   9. SanPham_Embedding (Lợi ghi)
   Vector lưu dạng nhị phân. Mỗi sản phẩm một vector.
   Lưu ý: trg_SanPham_ChanXoa phải xóa dòng ở bảng này trước khi xóa thật
   SanPham, nếu không khóa ngoại sẽ chặn lệnh DELETE.
   --------------------------------------------------------------------- */
CREATE TABLE SanPham_Embedding (
    MaSP   INT            NOT NULL,
    Vector VARBINARY(MAX) NOT NULL,
    CONSTRAINT PK_SanPham_Embedding PRIMARY KEY (MaSP),
    CONSTRAINT FK_Embedding_SanPham FOREIGN KEY (MaSP) REFERENCES SanPham(MaSP)
);
GO

/* ---------------------------------------------------------------------
   10. KhachHang_PhanNhom (Lợi ghi)
   R: số ngày từ lần mua gần nhất, F: số đơn, M: tổng tiền chi tiêu.
   --------------------------------------------------------------------- */
CREATE TABLE KhachHang_PhanNhom (
    MaKH INT           NOT NULL,
    R    INT           NOT NULL,
    F    INT           NOT NULL,
    M    DECIMAL(18,0) NOT NULL,
    Nhom NVARCHAR(50)  NULL,
    CONSTRAINT PK_KhachHang_PhanNhom PRIMARY KEY (MaKH),
    CONSTRAINT FK_PhanNhom_KhachHang FOREIGN KEY (MaKH) REFERENCES KhachHang(MaKH)
);
GO

/* ---------------------------------------------------------------------
   Kiểm tra nhanh: liệt kê các bảng vừa tạo
   --------------------------------------------------------------------- */
SELECT name, create_date FROM sys.tables ORDER BY name;
GO
