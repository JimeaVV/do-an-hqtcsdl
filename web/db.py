"""
web/db.py
Lớp gọi stored procedure cho web. Web không viết SQL truy vấn bảng trực tiếp:
mọi thao tác đều đi qua procedure trong sql/02_procedure.sql.
Cấu hình kết nối đọc từ file .env ở thư mục gốc repo.
"""
import os
import re

import pyodbc
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))


def _chuoi_ket_noi():
    return (
        f"DRIVER={{{os.getenv('DB_DRIVER', 'ODBC Driver 18 for SQL Server')}}};"
        f"SERVER={os.getenv('DB_SERVER', 'localhost')};"
        f"DATABASE={os.getenv('DB_NAME', 'ShopDB')};"
        f"Trusted_Connection={os.getenv('DB_TRUSTED_CONNECTION', 'yes')};"
        f"TrustServerCertificate={os.getenv('DB_TRUST_SERVER_CERTIFICATE', 'yes')};"
    )


def _ket_noi():
    # autocommit=True: procedure tự BEGIN TRAN / COMMIT / ROLLBACK.
    # Nếu để False, ROLLBACK trong procedure sẽ hủy luôn giao dịch bên ngoài.
    return pyodbc.connect(_chuoi_ket_noi(), autocommit=True)


class LoiNghiepVu(Exception):
    """Lỗi do procedure THROW (mã 50001 đến 50008), hiện được cho người dùng."""

    def __init__(self, ma, thong_bao):
        super().__init__(thong_bao)
        self.ma = ma
        self.thong_bao = thong_bao


def _doi_loi(e):
    """Đổi pyodbc.Error thành LoiNghiepVu nếu là lỗi THROW của nhóm."""
    van_ban = str(e.args[1] if len(e.args) > 1 else e)
    m = re.search(r"\[SQL Server\](.*?)\s*\((5000\d)\)", van_ban)
    if m:
        return LoiNghiepVu(int(m.group(2)), m.group(1).strip())
    m = re.search(r'CHECK constraint "(\w+)"', van_ban)
    if m:
        # Ràng buộc CHECK trong 01_tao_bang.sql chặn dữ liệu sai, ví dụ giá âm
        return LoiNghiepVu(547, f"Dữ liệu không hợp lệ, bị ràng buộc {m.group(1)} trong database chặn lại")
    return e


def _doc_bang(cur):
    cot = [c[0] for c in cur.description]
    return [dict(zip(cot, dong)) for dong in cur.fetchall()]


def _tham_so(tham_so):
    """{'MaSP': 1, 'Gia': 2} -> ('@MaSP = ?, @Gia = ?', [1, 2])"""
    ten = ", ".join(f"@{k} = ?" for k in tham_so)
    return ten, list(tham_so.values())


def goi(proc, **tham_so):
    """Gọi procedure, trả về result set đầu tiên dạng list[dict]. Không có bảng nào thì trả []."""
    return goi_nhieu(proc, **tham_so)[0]


def goi_nhieu(proc, **tham_so):
    """Gọi procedure trả nhiều result set, trả về list các list[dict]."""
    ten, gia_tri = _tham_so(tham_so)
    sql = f"SET NOCOUNT ON; EXEC {proc} {ten}"
    conn = _ket_noi()
    try:
        cur = conn.execute(sql, *gia_tri)
        cac_bang = []
        while True:
            if cur.description is not None:
                cac_bang.append(_doc_bang(cur))
            if not cur.nextset():
                break
        return cac_bang or [[]]
    except pyodbc.Error as e:
        raise _doi_loi(e) from e
    finally:
        conn.close()


def goi_output(proc, ten_output, kieu="INT", **tham_so):
    """Gọi procedure có một tham số OUTPUT, trả về giá trị của nó.
    pyodbc không đọc trực tiếp tham số OUTPUT nên khai báo biến rồi SELECT lại."""
    ten, gia_tri = _tham_so(tham_so)
    dau_phay = ", " if ten else ""
    sql = (f"SET NOCOUNT ON; DECLARE @kq {kieu}; "
           f"EXEC {proc} {ten}{dau_phay}@{ten_output} = @kq OUTPUT; SELECT @kq AS KetQua;")
    conn = _ket_noi()
    try:
        cur = conn.execute(sql, *gia_tri)
        while cur.description is None and cur.nextset():
            pass
        dong = cur.fetchone()
        return dong[0] if dong else None
    except pyodbc.Error as e:
        raise _doi_loi(e) from e
    finally:
        conn.close()


def tong_so(bang):
    """Các procedure LayDS trả cột TongSo (tổng số dòng trước khi phân trang)."""
    return int(bang[0]["TongSo"]) if bang else 0
