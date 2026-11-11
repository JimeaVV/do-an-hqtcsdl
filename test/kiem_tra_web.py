"""
test/kiem_tra_web.py
Kiểm tra tự động toàn bộ web và các procedure, transaction, trigger phía sau.

Chạy từ thư mục gốc repo (không cần mở web trước, script tự chạy Flask bên trong):
    .venv\\Scripts\\python test\\kiem_tra_web.py
    .venv\\Scripts\\python test\\kiem_tra_web.py --ai        # thêm phần tìm kiếm AI (nạp model, chậm hơn)
    .venv\\Scripts\\python test\\kiem_tra_web.py --giu-lai   # không dọn dữ liệu test, để mở web xem lại

Script tự tạo dữ liệu riêng tên "TEST ..." (1 danh mục, 2 sản phẩm, 2 khách, vài đơn)
nên không đụng dữ liệu thật. Cuối cùng xóa sạch dữ liệu đó, chỉ để lại các dòng
trong NhatKy vì nhật ký là để giữ.
"""
import os
import re
import sys
import time

GOC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, GOC)
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
try:
    sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
    pass

from web.app import app            # noqa: E402
from web.db import _ket_noi, goi   # noqa: E402

AI = "--ai" in sys.argv
GIU_LAI = "--giu-lai" in sys.argv
DAU = time.strftime("%H%M%S")     # đuôi riêng cho mỗi lần chạy để không trùng tên, email

ket_qua = []   # (mã, tên, đạt, ghi chú)


def kiem(ma, ten, dat, ghi_chu=""):
    ket_qua.append((ma, ten, bool(dat), ghi_chu))
    print(f"  [{'ĐẠT ' if dat else 'LỖI '}] {ma} {ten}" + (f"  ({ghi_chu})" if ghi_chu and not dat else ""))


def sql(cau, *tham_so):
    """Đọc trực tiếp bảng, chỉ dùng để đối chiếu kết quả (web thì luôn gọi procedure)."""
    conn = _ket_noi()
    try:
        cur = conn.execute(cau, *tham_so)
        return cur.fetchall() if cur.description else None
    finally:
        conn.close()


def ton_kho(ma_sp):
    return sql("SELECT TonKho FROM SanPham WHERE MaSP = ?", ma_sp)[0][0]


def so_nhat_ky():
    return sql("SELECT ISNULL(MAX(MaNK), 0) FROM NhatKy")[0][0]


c = app.test_client()


def gui(url, **du_lieu):
    """POST giống người bấm nút. Trả (mã HTTP, chỗ chuyển tới, danh sách thông báo flash)."""
    r = c.post(url, data=du_lieu)
    with c.session_transaction() as s:
        thong_bao = [t for _, t in s.pop("_flashes", [])]
    return r.status_code, r.headers.get("Location", ""), " | ".join(thong_bao)


# ====================================================================== 1. các trang
print("\n1. Mở các trang")
trang = ["/", "/san-pham", "/san-pham?q=a", "/san-pham?trang=2", "/san-pham/them", "/danh-muc",
         "/gio-hang", "/don-hang", "/don-hang?tt=ChoXuLy", "/don-hang?tt=HoanThanh", "/don-hang?tt=DaHuy",
         "/khach-hang", "/khach-hang?q=demo", "/nhat-ky", "/nhat-ky?tt=CanhBaoKho", "/doi-tuong-csdl",
         "/api/trang-thai-ai"]
for i, url in enumerate(trang, 1):
    r = c.get(url)
    kiem(f"T{i:02d}", f"GET {url}", r.status_code == 200, f"HTTP {r.status_code}")

r = c.get("/doi-tuong-csdl").get_data(as_text=True)
kiem("T18", "Trang Đối tượng CSDL liệt kê đủ 4 trigger",
     all(t in r for t in ["trg_SanPham_ChanXoa", "trg_SanPham_LichSuGia", "trg_DonHang_NhatKy", "trg_SanPham_CanhBaoKho"]))

# ====================================================================== 2. danh mục, sản phẩm
print("\n2. Danh mục và sản phẩm (CRUD, ràng buộc)")
ten_dm = f"TEST danh mục {DAU}"
_, _, tb = gui("/danh-muc", TenDanhMuc=ten_dm)
dm = goi("sp_DanhMuc_LayDS", TuKhoa=ten_dm, Trang=1, KichThuoc=5)
ma_dm = dm[0]["MaDanhMuc"] if dm else None
kiem("D01", "Thêm danh mục qua sp_DanhMuc_Them", ma_dm, tb)

_, _, tb = gui("/danh-muc", TenDanhMuc=ten_dm)
kiem("D02", "Thêm trùng tên danh mục bị chặn (50008)", "đã tồn tại" in tb, tb)

ten_sp1, ten_sp2 = f"TEST tai nghe {DAU}", f"TEST chuột {DAU}"
gui("/san-pham/them", MaDanhMuc=ma_dm, TenSP=ten_sp1, MoTa="Sản phẩm của script test", Gia=1000000, TonKho=10)
gui("/san-pham/them", MaDanhMuc=ma_dm, TenSP=ten_sp2, MoTa="", Gia=200000, TonKho=2)
sp1 = goi("sp_SanPham_LayDS", TuKhoa=ten_sp1, Trang=1, KichThuoc=5)
sp2 = goi("sp_SanPham_LayDS", TuKhoa=ten_sp2, Trang=1, KichThuoc=5)
ma_sp1 = sp1[0]["MaSP"] if sp1 else None
ma_sp2 = sp2[0]["MaSP"] if sp2 else None
kiem("S01", "Thêm sản phẩm qua sp_SanPham_Them", ma_sp1 and ma_sp2)
if not (ma_dm and ma_sp1 and ma_sp2):
    sys.exit("Không tạo được dữ liệu test, dừng. Kiểm tra lại database và 02_procedure.sql.")

r = c.get(f"/san-pham?q={ten_sp1}").get_data(as_text=True)
kiem("S02", "Tìm theo tên ra đúng sản phẩm vừa thêm", ten_sp1 in r)

# Lỗi ở form thì web vẽ lại form kèm thông báo ngay (không chuyển trang), nên đọc thẳng HTML
r = c.post("/san-pham/them", data=dict(MaDanhMuc=ma_dm, TenSP=f"TEST giá âm {DAU}", Gia=-5, TonKho=1))
kiem("S03", "Giá âm bị CHECK CK_SanPham_Gia chặn, web báo lỗi chứ không sập",
     r.status_code == 200 and "CK_SanPham_Gia" in r.get_data(as_text=True), f"HTTP {r.status_code}")

nk = so_nhat_ky()
gui(f"/san-pham/{ma_sp1}/sua", MaDanhMuc=ma_dm, TenSP=ten_sp1, MoTa="Sản phẩm của script test", Gia=1200000, TonKho=10)
ls = sql("SELECT GiaCu, GiaMoi FROM LichSuGia WHERE MaSP = ?", ma_sp1)
kiem("S04", "Sửa giá thì trigger trg_SanPham_LichSuGia ghi giá cũ và giá mới",
     ls and int(ls[-1][0]) == 1000000 and int(ls[-1][1]) == 1200000, str(ls))

gui(f"/san-pham/{ma_sp1}/sua", MaDanhMuc=ma_dm, TenSP=ten_sp1 + " ", MoTa="đổi mô tả", Gia=1200000, TonKho=10)
ls2 = sql("SELECT COUNT(*) FROM LichSuGia WHERE MaSP = ?", ma_sp1)[0][0]
kiem("S05", "Sửa mà giá không đổi thì không ghi thêm lịch sử giá", ls2 == 1, f"{ls2} dòng")

# ====================================================================== 3. khách hàng
print("\n3. Khách hàng")
email1, email2 = f"test{DAU}a@vidu.vn", f"test{DAU}b@vidu.vn"
gui("/khach-hang/luu", MaKH="", HoTen="TEST Nguyễn Văn A", Email=email1, SDT="0900000001")
gui("/khach-hang/luu", MaKH="", HoTen="TEST Trần Thị B", Email=email2, SDT="")
kh1 = goi("sp_KhachHang_LayDS", TuKhoa=email1, Trang=1, KichThuoc=5)
kh2 = goi("sp_KhachHang_LayDS", TuKhoa=email2, Trang=1, KichThuoc=5)
ma_kh1 = kh1[0]["MaKH"] if kh1 else None
ma_kh2 = kh2[0]["MaKH"] if kh2 else None
kiem("K01", "Thêm khách hàng qua sp_KhachHang_Them", ma_kh1 and ma_kh2)

_, _, tb = gui("/khach-hang/luu", MaKH="", HoTen="TEST trùng", Email=email1, SDT="")
kiem("K02", "Email trùng bị chặn (50004)", "Email đã tồn tại" in tb, tb)

gui("/khach-hang/luu", MaKH=ma_kh2, HoTen="TEST Trần Thị B (đã sửa)", Email=email2, SDT="0900000002")
kh2 = goi("sp_KhachHang_LayDS", TuKhoa=email2, Trang=1, KichThuoc=5)
kiem("K03", "Sửa khách hàng qua sp_KhachHang_Sua", kh2 and "đã sửa" in kh2[0]["HoTen"])

# ====================================================================== 4. đặt hàng, transaction
print("\n4. Đặt hàng, hủy, thanh toán (transaction)")
gui("/gio-hang", hanh_dong="chon_khach", MaKH=ma_kh1, HoTen="TEST Nguyễn Văn A", Email=email1)

nk = so_nhat_ky()
gui(f"/gio-hang/them/{ma_sp1}", SoLuong=7)
_, toi, tb = gui("/dat-hang")
m = re.search(r"/don-hang/(\d+)", toi)
don1 = int(m.group(1)) if m else None
kiem("G01", "Đặt hàng thành công qua sp_DatHang, chuyển tới trang chi tiết đơn", don1, tb)
kiem("G02", "Tồn kho bị trừ đúng 7 (10 còn 3)", ton_kho(ma_sp1) == 3, f"tồn {ton_kho(ma_sp1)}")
moi = sql("SELECT Bang, ThaoTac, NoiDung FROM NhatKy WHERE MaNK > ?", nk)
kiem("G03", "Trigger trg_DonHang_NhatKy ghi 'Them' cho đơn mới",
     any(b == "DonHang" and t == "Them" and str(don1) in n for b, t, n in moi))
kiem("G04", "Trigger trg_SanPham_CanhBaoKho cảnh báo khi kho tụt dưới 5",
     any(t == "CanhBaoKho" and str(ma_sp1) in n for _, t, n in moi))
r = c.get(f"/don-hang/{don1}").get_data(as_text=True)
kiem("G05", "Trang chi tiết đơn hiện sản phẩm và tổng tiền", ten_sp1 in r and "8.400.000" in r)

# Giỏ có 2 món: món 1 đủ hàng, món 2 thiếu hàng -> cả đơn phải ROLLBACK
don_truoc = sql("SELECT COUNT(*) FROM DonHang WHERE MaKH = ?", ma_kh1)[0][0]
gui(f"/gio-hang/them/{ma_sp1}", SoLuong=1)
gui(f"/gio-hang/them/{ma_sp2}", SoLuong=5)
_, toi, tb = gui("/dat-hang")
kiem("G06", "Thiếu hàng ở 1 món thì báo lỗi 'Không đủ hàng' và ROLLBACK", "ROLLBACK" in tb, tb)
kiem("G07", "Sau ROLLBACK, món đủ hàng cũng không bị trừ kho (vẫn 3)", ton_kho(ma_sp1) == 3, f"tồn {ton_kho(ma_sp1)}")
kiem("G08", "Sau ROLLBACK, không có đơn nào được tạo",
     sql("SELECT COUNT(*) FROM DonHang WHERE MaKH = ?", ma_kh1)[0][0] == don_truoc)
gui("/gio-hang", hanh_dong="xoa_het")

nk = so_nhat_ky()
_, _, tb = gui(f"/don-hang/{don1}/huy")
kiem("G09", "Hủy đơn qua sp_HuyDon, kho được cộng lại (về 10)", ton_kho(ma_sp1) == 10, f"{tb}; tồn {ton_kho(ma_sp1)}")
moi = sql("SELECT ThaoTac, NoiDung FROM NhatKy WHERE MaNK > ?", nk)
kiem("G10", "Trigger ghi 'Sua' với trạng thái ChoXuLy -> DaHuy",
     any(t == "Sua" and "DaHuy" in n for t, n in moi))
_, _, tb = gui(f"/don-hang/{don1}/huy")
kiem("G11", "Hủy lần 2 bị chặn (50006), kho không bị cộng hai lần", "chờ xử lý" in tb and ton_kho(ma_sp1) == 10, tb)

gui(f"/gio-hang/them/{ma_sp1}", SoLuong=2)
_, toi, _ = gui("/dat-hang")
m = re.search(r"/don-hang/(\d+)", toi)
don2 = int(m.group(1)) if m else None
_, _, tb = gui(f"/don-hang/{don2}/thanh-toan", PhuongThuc="Chuyển khoản")
tt = sql("SELECT d.TrangThai, t.SoTien FROM DonHang d JOIN ThanhToan t ON t.MaDon = d.MaDon WHERE d.MaDon = ?", don2)
kiem("G12", "Thanh toán qua sp_ThanhToan: đơn thành HoanThanh, số tiền do database tự tính",
     tt and tt[0][0] == "HoanThanh" and int(tt[0][1]) == 2400000, f"{tb}; {tt}")
_, _, tb = gui(f"/don-hang/{don2}/thanh-toan", PhuongThuc="Thẻ")
kiem("G13", "Thanh toán lần 2 bị chặn (50006)", "chờ xử lý" in tb, tb)
_, _, tb = gui(f"/don-hang/{don2}/huy")
kiem("G14", "Không hủy được đơn đã thanh toán (50006)", "chờ xử lý" in tb, tb)

# ====================================================================== 5. xóa, trigger chặn xóa
print("\n5. Xóa (trigger INSTEAD OF DELETE và các ràng buộc)")
_, _, tb = gui(f"/khach-hang/{ma_kh1}/xoa")
kiem("X01", "Không xóa được khách đã có đơn (50005)", "đã có đơn hàng" in tb, tb)
_, _, tb = gui(f"/khach-hang/{ma_kh2}/xoa")
kiem("X02", "Xóa khách chưa có đơn", not goi("sp_KhachHang_LayDS", TuKhoa=email2, Trang=1, KichThuoc=5), tb)
ma_kh2 = None

_, _, tb = gui(f"/san-pham/{ma_sp1}/xoa")
con = sql("SELECT DaXoa FROM SanPham WHERE MaSP = ?", ma_sp1)
kiem("X03", "Sản phẩm đã có đơn: trigger chỉ ẩn (DaXoa = 1), không xóa hẳn", con and con[0][0] == 1, tb)
kiem("X04", "Sản phẩm bị ẩn không còn hiện trong danh sách",
     not goi("sp_SanPham_LayDS", TuKhoa=ten_sp1, Trang=1, KichThuoc=5))
_, _, tb = gui(f"/san-pham/{ma_sp2}/xoa")
kiem("X05", "Sản phẩm chưa có đơn: xóa hẳn khỏi bảng", not sql("SELECT 1 FROM SanPham WHERE MaSP = ?", ma_sp2), tb)
_, _, tb = gui(f"/danh-muc/{ma_dm}/xoa")
kiem("X06", "Không xóa được danh mục còn sản phẩm (50003)", "còn sản phẩm" in tb, tb)

# ====================================================================== 6. AI
if AI:
    print("\n6. Tìm kiếm AI (nạp model, chờ một lúc)")
    r = c.get("/san-pham?ai=1&q=tai+nghe+chống+ồn")
    kiem("A01", "Tìm theo nghĩa trả trang có cột Độ giống", r.status_code == 200 and "Độ giống" in r.get_data(as_text=True))

# ====================================================================== dọn dữ liệu test
if GIU_LAI:
    print(f"\nGiữ lại dữ liệu test: danh mục {ma_dm}, sản phẩm {ma_sp1}, khách {ma_kh1}, đơn {don1} và {don2}.")
else:
    conn = _ket_noi()
    conn.autocommit = False
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM ThanhToan WHERE MaDon IN (SELECT MaDon FROM DonHang WHERE MaKH = ?)", ma_kh1)
        cur.execute("DELETE FROM ChiTietDonHang WHERE MaDon IN (SELECT MaDon FROM DonHang WHERE MaKH = ?)", ma_kh1)
        cur.execute("DELETE FROM DonHang WHERE MaKH = ?", ma_kh1)
        cur.execute("DELETE FROM KhachHang_PhanNhom WHERE MaKH = ?", ma_kh1)
        cur.execute("DELETE FROM KhachHang WHERE MaKH = ?", ma_kh1)
        cur.execute("DELETE FROM LichSuGia WHERE MaSP IN (SELECT MaSP FROM SanPham WHERE MaDanhMuc = ?)", ma_dm)
        cur.execute("DELETE FROM SanPham_Embedding WHERE MaSP IN (SELECT MaSP FROM SanPham WHERE MaDanhMuc = ?)", ma_dm)
        cur.execute("DELETE FROM SanPham WHERE MaDanhMuc = ?", ma_dm)   # hết đơn rồi nên trigger xóa hẳn
        cur.execute("DELETE FROM DanhMuc WHERE MaDanhMuc = ?", ma_dm)
        conn.commit()
        print("\nĐã dọn dữ liệu test (NhatKy giữ nguyên).")
    except Exception as e:
        conn.rollback()
        print(f"\nKhông dọn được dữ liệu test: {e}")
    finally:
        conn.close()

# ====================================================================== tổng kết
dat = sum(1 for k in ket_qua if k[2])
print(f"\nKết quả: {dat}/{len(ket_qua)} đạt")
for ma, ten, ok, ghi in ket_qua:
    if not ok:
        print(f"  LỖI {ma} {ten}: {ghi}")
sys.exit(0 if dat == len(ket_qua) else 1)
