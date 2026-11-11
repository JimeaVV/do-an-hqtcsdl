"""
web/ai_bridge.py
Gọi hai hàm AI của Lợi (ai/tim_kiem.py, ai/phan_nhom.py).
Thư viện AI nặng nên chỉ import khi cần, và nạp sẵn model ở luồng nền
lúc web khởi động để lần tìm đầu tiên không phải chờ.
"""
import threading

_khoa = threading.Lock()
_trang_thai = {"san_sang": False, "loi": None}


def _nap():
    with _khoa:
        if _trang_thai["san_sang"]:
            return
        try:
            from ai import tim_kiem as tk
            tk.nap_vector()
            _trang_thai["san_sang"] = True
            _trang_thai["loi"] = None
        except Exception as e:  # thiếu thư viện, chưa có vector, lỗi kết nối...
            _trang_thai["loi"] = str(e)


def nap_nen():
    threading.Thread(target=_nap, daemon=True).start()


def trang_thai():
    return dict(_trang_thai)


def tim_kiem(cau_hoi, k=10):
    """Trả về [(MaSP, diem), ...]. Ném RuntimeError nếu module AI chưa dùng được."""
    _nap()
    if not _trang_thai["san_sang"]:
        raise RuntimeError(_trang_thai["loi"] or "Module AI chưa sẵn sàng")
    from ai import tim_kiem as tk
    return tk.tim_kiem(cau_hoi, k=k)


def nap_lai_vector():
    """Gọi sau khi chạy lại ai/tao_embedding.py để web thấy vector mới."""
    from ai import tim_kiem as tk
    with _khoa:
        tk.nap_vector()


def chay_phan_nhom(k=4):
    from ai import phan_nhom as pn
    return pn.chay_phan_nhom(k=k)
