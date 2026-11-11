"""
web/app.py
Web quản lý cửa hàng đồ công nghệ (Flask + Bootstrap).
Chạy từ thư mục gốc repo:  .venv\\Scripts\\python web\\app.py   rồi mở http://localhost:5055
"""
import json
import math
from datetime import datetime
import os
import sys
import zlib

# Cho phép import "web.*" và "ai.*" dù chạy file này trực tiếp
GOC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if GOC not in sys.path:
    sys.path.insert(0, GOC)

from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for

from web import ai_bridge
from web.db import LoiNghiepVu, goi, goi_nhieu, goi_output, tong_so

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET", "do-an-hqtcsdl-dev")
app.config["TEMPLATES_AUTO_RELOAD"] = True

KICH_THUOC = 20
TRANG_THAI = {
    "ChoXuLy": ("Chờ xử lý", "warning"),
    "HoanThanh": ("Hoàn thành", "success"),
    "DaHuy": ("Đã hủy", "secondary"),
}
PHUONG_THUC = ["Tiền mặt", "Chuyển khoản", "Thẻ"]


# ------------------------------------------------------------------ tiện ích
@app.template_filter("tien")
def dinh_dang_tien(v):
    if v is None:
        return "0 ₫"
    return f"{float(v):,.0f}".replace(",", ".") + " ₫"


@app.template_filter("tien_gon")
def tien_gon(v):
    """35951746364000 -> '35.951,7 tỷ ₫' cho ô số liệu lớn; số nhỏ hơn 1 tỷ giữ nguyên."""
    v = float(v or 0)
    if v < 1e9:
        return dinh_dang_tien(v)
    return f"{v / 1e9:,.1f}".replace(",", " ").replace(".", ",").replace(" ", ".") + " tỷ ₫"


@app.template_filter("so")
def dinh_dang_so(v):
    return f"{int(v or 0):,}".replace(",", ".")


@app.template_filter("ngay")
def dinh_dang_ngay(v):
    return v.strftime("%d/%m/%Y %H:%M") if v else ""


@app.template_filter("chu_dau")
def chu_dau(ten):
    """'Nguyễn Văn An' -> 'NA', dùng cho ô tròn thay ảnh đại diện."""
    tu = str(ten or "?").split() or ["?"]
    return (tu[0][0] + (tu[-1][0] if len(tu) > 1 else "")).upper()


@app.template_filter("sac")
def sac(v):
    """Số 0..9 ổn định theo giá trị (tên danh mục, mã khách) để chọn tông màu trong style.css."""
    return zlib.crc32(str(v).encode("utf-8")) % 10


@app.template_filter("thap_phan")
def thap_phan(v, so_le=1):
    """7.04 -> '7,0' (dấu phẩy thập phân kiểu Việt Nam)."""
    return f"{float(v or 0):.{so_le}f}".replace(".", ",")


@app.context_processor
def bien_chung():
    gio = session.get("gio", {})
    return {
        "TRANG_THAI": TRANG_THAI,
        "so_mon_gio": sum(gio.values()),
        "trang_hien_tai": request.endpoint or "",
    }


def so_trang():
    try:
        return max(1, int(request.args.get("trang", 1)))
    except ValueError:
        return 1


def phan_trang(bang, trang):
    tong = tong_so(bang)
    return {"trang": trang, "tong": tong, "so_trang": max(1, math.ceil(tong / KICH_THUOC))}


def chu_hoac_none(ten):
    v = request.values.get(ten, "").strip()
    return v or None


def so_hoac_none(ten):
    v = request.values.get(ten, "").strip()
    return int(v) if v.isdigit() else None


def bao_loi(e):
    flash(e.thong_bao if isinstance(e, LoiNghiepVu) else f"Lỗi: {e}", "danger")


# ------------------------------------------------------------------ tổng quan
def _chia_100(cac_so):
    """Chia 100 ô theo tỷ lệ các số (phương pháp số dư lớn nhất) để vẽ lưới 10 x 10."""
    tong = sum(cac_so)
    if not tong:
        return [0] * len(cac_so)
    tho = [x * 100 / tong for x in cac_so]
    o = [int(t) for t in tho]
    for i in sorted(range(len(tho)), key=lambda i: tho[i] - o[i], reverse=True)[:100 - sum(o)]:
        o[i] += 1
    return o


@app.route("/")
def tong_quan():
    so_lieu, top5, doanh_thu = goi_nhieu("sp_ThongKe_Dashboard")
    luc = datetime.now()
    bieu_do = {
        "thang": [f"{r['Thang']:02d}/{r['Nam']}" for r in doanh_thu],
        "doanh_thu": [float(r["DoanhThu"]) for r in doanh_thu],
    }
    s = so_lieu[0]
    tong = max(1, s["TongDon"])
    ty_le = [(ma, s[cot], s[cot] * 100 / tong) for ma, cot in
             [("HoanThanh", "DonHoanThanh"), ("ChoXuLy", "DonChoXuLy"), ("DaHuy", "DonDaHuy")]]
    # Lưới 100 ô: mỗi ô là 1% số đơn
    o_vuong = [ma for (ma, _, _), n in zip(ty_le, _chia_100([t[1] for t in ty_le])) for _ in range(n)]

    # Phần dưới chỉ tính lại từ 6 giá trị doanh thu tháng đã lấy, không gọi thêm dữ liệu.
    # Tháng cuối có thể là tháng đang chạy (chưa đủ ngày) nên tách riêng để không so sánh lệch.
    dang_chay = bool(doanh_thu) and (doanh_thu[-1]["Nam"], doanh_thu[-1]["Thang"]) == (luc.year, luc.month)
    du = bieu_do["doanh_thu"][:-1] if dang_chay else bieu_do["doanh_thu"]
    nhan_du = bieu_do["thang"][:-1] if dang_chay else bieu_do["thang"]
    bieu_do["dang_chay"] = dang_chay
    bieu_do["trung_binh"] = sum(du) / len(du) if du else None
    so_sanh = None
    if len(du) >= 2 and du[-2] > 0:
        so_sanh = {"thang": nhan_du[-1], "truoc": nhan_du[-2], "gia_tri": du[-1],
                   "phan_tram": (du[-1] - du[-2]) * 100 / du[-2]}
    tia = None  # đường nhỏ trong ô doanh thu, vẽ trong khung 120 x 36
    if len(du) >= 3:
        thap, cao = min(du), max(du)
        diem = [(round(i * 120 / (len(du) - 1), 1), round(31 - (v - thap) / ((cao - thap) or 1) * 26, 1))
                for i, v in enumerate(du)]
        tia = {"duong": " ".join(f"{x},{y}" for x, y in diem), "cuoi": diem[-1],
               "tu": nhan_du[0], "den": nhan_du[-1]}
    return render_template("tong_quan.html", s=s, top5=top5, bieu_do=bieu_do, ty_le=ty_le, luc=luc,
                           o_vuong=o_vuong, so_sanh=so_sanh, tia=tia)


# ------------------------------------------------------------------ sản phẩm
@app.route("/san-pham")
def san_pham():
    tu_khoa = chu_hoac_none("q")
    ma_dm = so_hoac_none("dm")
    che_do_ai = request.args.get("ai") == "1"
    trang = so_trang()
    danh_muc = goi("sp_DanhMuc_LayDS", Trang=1, KichThuoc=200)
    trang_thai_ai = ai_bridge.trang_thai()

    if che_do_ai and tu_khoa:
        try:
            ket_qua = ai_bridge.tim_kiem(tu_khoa, k=12)
            diem = {ma: d for ma, d in ket_qua}
            ds = goi("sp_SanPham_LayTheoDS", DSMaSP=json.dumps([ma for ma, _ in ket_qua]))
            for sp in ds:
                sp["DiemAI"] = diem.get(sp["MaSP"], 0)
        except Exception as e:
            flash(f"Tìm kiếm AI chưa dùng được: {e}", "warning")
            ds = []
        pt = None
    else:
        ds = goi("sp_SanPham_LayDS", TuKhoa=tu_khoa, MaDanhMuc=ma_dm, Trang=trang, KichThuoc=KICH_THUOC)
        pt = phan_trang(ds, trang)
    return render_template("san_pham.html", ds=ds, pt=pt, danh_muc=danh_muc, q=tu_khoa or "", dm=ma_dm,
                           che_do_ai=che_do_ai, trang_thai_ai=trang_thai_ai)


@app.route("/san-pham/them", methods=["GET", "POST"])
@app.route("/san-pham/<int:ma>/sua", methods=["GET", "POST"])
def san_pham_form(ma=None):
    danh_muc = goi("sp_DanhMuc_LayDS", Trang=1, KichThuoc=200)
    if request.method == "POST":
        f = request.form
        try:
            gia_tri = dict(MaDanhMuc=int(f["MaDanhMuc"]), TenSP=f["TenSP"].strip(), MoTa=f.get("MoTa", "").strip() or None,
                           Gia=int(f["Gia"]), TonKho=int(f["TonKho"]))
            if ma:
                goi("sp_SanPham_Sua", MaSP=ma, **gia_tri)
                flash(f"Đã cập nhật sản phẩm #{ma}.", "success")
            else:
                moi = goi_output("sp_SanPham_Them", "MaSP", **gia_tri)
                flash(f"Đã thêm sản phẩm #{moi}.", "success")
            return redirect(url_for("san_pham"))
        except (LoiNghiepVu, ValueError) as e:
            bao_loi(e if isinstance(e, LoiNghiepVu) else LoiNghiepVu(0, "Giá và tồn kho phải là số nguyên không âm."))
        sp = dict(request.form)
    else:
        sp = None
        if ma:
            ds = goi("sp_SanPham_LayTheoMa", MaSP=ma)
            if not ds:
                flash("Sản phẩm không tồn tại hoặc đã bị ẩn.", "warning")
                return redirect(url_for("san_pham"))
            sp = ds[0]
    return render_template("san_pham_form.html", sp=sp, ma=ma, danh_muc=danh_muc)


@app.route("/san-pham/<int:ma>/xoa", methods=["POST"])
def san_pham_xoa(ma):
    try:
        kq = goi("sp_SanPham_Xoa", MaSP=ma)
        if kq and kq[0]["KetQua"] == "DaAn":
            flash(f"Sản phẩm #{ma} đã có đơn hàng nên chỉ được ẩn (trigger trg_SanPham_ChanXoa).", "info")
        else:
            flash(f"Đã xóa hẳn sản phẩm #{ma}.", "success")
    except LoiNghiepVu as e:
        bao_loi(e)
    return redirect(request.referrer or url_for("san_pham"))


# ------------------------------------------------------------------ danh mục
@app.route("/danh-muc", methods=["GET", "POST"])
def danh_muc():
    if request.method == "POST":
        ten = request.form.get("TenDanhMuc", "").strip()
        ma = so_hoac_none("MaDanhMuc")
        try:
            if ma:
                goi("sp_DanhMuc_Sua", MaDanhMuc=ma, TenDanhMuc=ten)
                flash("Đã đổi tên danh mục.", "success")
            else:
                goi_output("sp_DanhMuc_Them", "MaDanhMuc", TenDanhMuc=ten)
                flash("Đã thêm danh mục.", "success")
        except LoiNghiepVu as e:
            bao_loi(e)
        return redirect(url_for("danh_muc"))
    ds = goi("sp_DanhMuc_LayDS", TuKhoa=chu_hoac_none("q"), Trang=1, KichThuoc=200)
    return render_template("danh_muc.html", ds=ds, q=request.args.get("q", ""))


@app.route("/danh-muc/<int:ma>/xoa", methods=["POST"])
def danh_muc_xoa(ma):
    try:
        goi("sp_DanhMuc_Xoa", MaDanhMuc=ma)
        flash("Đã xóa danh mục.", "success")
    except LoiNghiepVu as e:
        bao_loi(e)
    return redirect(url_for("danh_muc"))


# ------------------------------------------------------------------ giỏ hàng, đặt hàng
@app.route("/gio-hang/them/<int:ma>", methods=["POST"])
def gio_them(ma):
    gio = session.get("gio", {})
    gio[str(ma)] = gio.get(str(ma), 0) + max(1, int(request.form.get("SoLuong", 1)))
    session["gio"] = gio
    flash(f"Đã thêm sản phẩm #{ma} vào giỏ.", "success")
    return redirect(request.referrer or url_for("san_pham"))


@app.route("/gio-hang", methods=["GET", "POST"])
def gio_hang():
    gio = session.get("gio", {})
    if request.method == "POST":
        hanh_dong = request.form.get("hanh_dong")
        if hanh_dong == "cap_nhat":
            for ma in list(gio):
                sl = request.form.get(f"sl_{ma}", "").strip()
                if sl.isdigit() and int(sl) > 0:
                    gio[ma] = int(sl)
                else:
                    gio.pop(ma)
            session["gio"] = gio
        elif hanh_dong == "xoa_het":
            session["gio"] = {}
        elif hanh_dong == "chon_khach":
            session["khach"] = {"MaKH": so_hoac_none("MaKH"), "HoTen": request.form.get("HoTen", ""),
                                "Email": request.form.get("Email", "")}
        return redirect(url_for("gio_hang"))

    mon = []
    if gio:
        ds = goi("sp_SanPham_LayTheoDS", DSMaSP=json.dumps([int(m) for m in gio]))
        for sp in ds:
            sp["SoLuong"] = gio[str(sp["MaSP"])]
            mon.append(sp)
    khach = session.get("khach")
    q_kh = chu_hoac_none("q_kh")
    ket_qua_kh = goi("sp_KhachHang_LayDS", TuKhoa=q_kh, Trang=1, KichThuoc=8) if q_kh else []
    tong = sum(float(m["Gia"]) * m["SoLuong"] for m in mon)
    return render_template("gio_hang.html", mon=mon, tong=tong, khach=khach, q_kh=q_kh or "", ket_qua_kh=ket_qua_kh)


@app.route("/dat-hang", methods=["POST"])
def dat_hang():
    gio = session.get("gio", {})
    ma_kh = (session.get("khach") or {}).get("MaKH")
    if not gio or not ma_kh:
        flash("Cần chọn khách hàng và có ít nhất một sản phẩm trong giỏ.", "warning")
        return redirect(url_for("gio_hang"))
    gio_json = json.dumps([{"MaSP": int(m), "SoLuong": sl} for m, sl in gio.items()])
    try:
        ma_don = goi_output("sp_DatHang", "MaDon", MaKH=ma_kh, GioHang=gio_json)
        session["gio"] = {}
        flash(f"Đặt hàng thành công: đơn #{ma_don}. Kho đã được trừ trong cùng một giao dịch.", "success")
        return redirect(url_for("don_hang_chi_tiet", ma=ma_don))
    except LoiNghiepVu as e:
        flash(f"{e.thong_bao}. Giao dịch đã ROLLBACK, tồn kho không thay đổi.", "danger")
        return redirect(url_for("gio_hang"))


# ------------------------------------------------------------------ đơn hàng
@app.route("/don-hang")
def don_hang():
    trang = so_trang()
    trang_thai = chu_hoac_none("tt")
    ma_kh = so_hoac_none("kh")
    ds = goi("sp_DonHang_LayDS", MaKH=ma_kh, TrangThai=trang_thai, Trang=trang, KichThuoc=KICH_THUOC)
    return render_template("don_hang.html", ds=ds, pt=phan_trang(ds, trang), tt=trang_thai, kh=ma_kh or "")


@app.route("/don-hang/<int:ma>")
def don_hang_chi_tiet(ma):
    try:
        don, chi_tiet = goi_nhieu("sp_DonHang_LayChiTiet", MaDon=ma)
    except LoiNghiepVu as e:
        bao_loi(e)
        return redirect(url_for("don_hang"))
    return render_template("don_hang_chi_tiet.html", d=don[0], chi_tiet=chi_tiet, phuong_thuc=PHUONG_THUC)


@app.route("/don-hang/<int:ma>/huy", methods=["POST"])
def don_hang_huy(ma):
    try:
        goi("sp_HuyDon", MaDon=ma)
        flash(f"Đã hủy đơn #{ma} và cộng lại tồn kho.", "success")
    except LoiNghiepVu as e:
        bao_loi(e)
    return redirect(url_for("don_hang_chi_tiet", ma=ma))


@app.route("/don-hang/<int:ma>/thanh-toan", methods=["POST"])
def don_hang_thanh_toan(ma):
    try:
        ma_tt = goi_output("sp_ThanhToan", "MaTT", MaDon=ma, PhuongThuc=request.form.get("PhuongThuc", PHUONG_THUC[0]))
        flash(f"Đã thanh toán đơn #{ma} (mã thanh toán {ma_tt}).", "success")
    except LoiNghiepVu as e:
        bao_loi(e)
    return redirect(url_for("don_hang_chi_tiet", ma=ma))


# ------------------------------------------------------------------ khách hàng
@app.route("/khach-hang")
def khach_hang():
    trang = so_trang()
    q = chu_hoac_none("q")
    ds = goi("sp_KhachHang_LayDS", TuKhoa=q, Trang=trang, KichThuoc=KICH_THUOC)
    nhom = goi("sp_PhanNhom_ThongKe")
    lon_nhat = max([int(n["SoKhachHang"]) for n in nhom] or [1])
    return render_template("khach_hang.html", ds=ds, pt=phan_trang(ds, trang), q=q or "", nhom=nhom, lon_nhat=lon_nhat)


@app.route("/khach-hang/luu", methods=["POST"])
def khach_hang_luu():
    """Form thêm/sửa nằm trong hộp thoại ở trang danh sách; MaKH rỗng là thêm mới."""
    f = request.form
    ma = so_hoac_none("MaKH")
    gia_tri = dict(HoTen=f["HoTen"].strip(), Email=f["Email"].strip(), SDT=f.get("SDT", "").strip() or None)
    try:
        if ma:
            goi("sp_KhachHang_Sua", MaKH=ma, **gia_tri)
            flash(f"Đã cập nhật khách hàng #{ma}.", "success")
        else:
            moi = goi_output("sp_KhachHang_Them", "MaKH", **gia_tri)
            flash(f"Đã thêm khách hàng #{moi}.", "success")
    except LoiNghiepVu as e:
        bao_loi(e)
    return redirect(request.referrer or url_for("khach_hang"))


@app.route("/khach-hang/<int:ma>/xoa", methods=["POST"])
def khach_hang_xoa(ma):
    try:
        goi("sp_KhachHang_Xoa", MaKH=ma)
        flash(f"Đã xóa khách hàng #{ma}.", "success")
    except LoiNghiepVu as e:
        bao_loi(e)
    return redirect(request.referrer or url_for("khach_hang"))


@app.route("/khach-hang/phan-nhom", methods=["POST"])
def khach_hang_phan_nhom():
    try:
        kq = ai_bridge.chay_phan_nhom(k=4)
        flash("Đã phân nhóm lại: " + ", ".join(f"{k} {v:,}".replace(",", ".") for k, v in kq.items()), "success")
    except Exception as e:
        flash(f"Chưa chạy được phân nhóm: {e}", "danger")
    return redirect(url_for("khach_hang"))


# ------------------------------------------------------------------ nhật ký, đối tượng CSDL
@app.route("/nhat-ky")
def nhat_ky():
    trang = so_trang()
    bang, thao_tac = chu_hoac_none("bang"), chu_hoac_none("tt")
    ds = goi("sp_NhatKy_LayDS", Bang=bang, ThaoTac=thao_tac, Trang=trang, KichThuoc=KICH_THUOC)
    return render_template("nhat_ky.html", ds=ds, pt=phan_trang(ds, trang), bang=bang or "", tt=thao_tac or "")


@app.route("/doi-tuong-csdl")
def doi_tuong():
    ds = goi("sp_DoiTuongCSDL")
    nhom = {}
    for r in ds:
        nhom.setdefault(r["Loai"], []).append(r)
    return render_template("doi_tuong.html", nhom=nhom)


@app.route("/api/trang-thai-ai")
def api_trang_thai_ai():
    return jsonify(ai_bridge.trang_thai())


if __name__ == "__main__":
    ai_bridge.nap_nen()
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", 5055)), debug=False)
