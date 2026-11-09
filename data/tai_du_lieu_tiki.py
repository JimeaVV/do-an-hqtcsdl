"""
data/tai_du_lieu_tiki.py
Tải danh mục sản phẩm đồ công nghệ thực tế từ sàn thương mại điện tử Tiki (Cách C).
Lưu kết quả ra file CSV: data/sanpham_tiki_congnghe.csv
Sau đó cập nhật vào bảng DanhMuc và SanPham trong cơ sở dữ liệu ShopDB.
"""

import sys
import os
import re
import html
import time
import json
import urllib.request
import pandas as pd

# Thêm thư mục gốc vào path để import db_helper
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from ai.db_helper import get_connection

CATEGORIES = [
    {"id": 1815, "name": "Thiết bị số & Phụ kiện", "pages": 2},
    {"id": 1789, "name": "Điện thoại & Máy tính bảng", "pages": 2},
    {"id": 1846, "name": "Laptop & Thiết bị tin học", "pages": 2},
    {"id": 4221, "name": "Thiết bị thông minh & Âm thanh", "pages": 2},
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*"
}

def clean_html(raw_html):
    if not raw_html:
        return ""
    # Xóa thẻ html
    text = re.sub(r"<[^>]+>", " ", raw_html)
    text = html.unescape(text)
    # Rút gọn khoảng trắng
    text = re.sub(r"\s+", " ", text).strip()
    return text

def tai_san_pham_tiki(max_per_cat=35):
    """Tải sản phẩm thực tế từ API Tiki."""
    san_pham_list = []

    for cat in CATEGORIES:
        cat_id = cat["id"]
        cat_name = cat["name"]
        print(f"[*] Đang lấy danh sách sản phẩm nhóm '{cat_name}' (ID: {cat_id})...")
        count = 0

        for page in range(1, cat["pages"] + 1):
            if count >= max_per_cat:
                break

            url_list = f"https://tiki.vn/api/personalish/v1/blocks/listings?limit=40&category={cat_id}&page={page}"
            try:
                req = urllib.request.Request(url_list, headers=HEADERS)
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    items = data.get("data", [])

                for item in items:
                    if count >= max_per_cat:
                        break

                    prod_id = item.get("id")
                    name = item.get("name", "").strip()
                    price = item.get("price", 0)

                    if not name or price <= 0:
                        continue

                    # Gọi API chi tiết để lấy mô tả đầy đủ
                    url_detail = f"https://tiki.vn/api/v2/products/{prod_id}"
                    mota = ""
                    try:
                        req_det = urllib.request.Request(url_detail, headers=HEADERS)
                        with urllib.request.urlopen(req_det, timeout=8) as r_det:
                            det_data = json.loads(r_det.read().decode("utf-8"))
                            raw_desc = det_data.get("description", "")
                            mota = clean_html(raw_desc)
                            # Cắt ngắn mô tả trong khoảng 200-500 ký tự súc tích
                            if len(mota) > 500:
                                mota = mota[:500] + "..."
                        time.sleep(0.1) # Tránh rate limit
                    except Exception:
                        mota = clean_html(item.get("short_description", "")) or f"Sản phẩm {name} chất lượng cao chính hãng."

                    if not mota:
                        mota = f"Sản phẩm {name} chính hãng, bảo hành đầy đủ, giá tốt."

                    san_pham_list.append({
                        "TenDanhMuc": cat_name,
                        "TenSP": name,
                        "MoTa": mota,
                        "Gia": int(price),
                        "TonKho": 100
                    })
                    count += 1
            except Exception as e:
                print(f"[!] Lỗi khi lấy trang {page} của danh mục {cat_name}: {e}")

    df = pd.DataFrame(san_pham_list)
    out_csv = os.path.join(current_dir, "sanpham_tiki_congnghe.csv")
    df.to_csv(out_csv, index=False, encoding="utf-8-sig")
    print(f"[+] Đã tải và lưu {len(df)} sản phẩm Tiki thực tế vào file: {out_csv}")
    return df

def cap_nhat_database(csv_path=None):
    """
    Cập nhật dữ liệu sản phẩm từ CSV vào bảng SanPham trong ShopDB.
    Để bảo toàn liên kết với 500.000 đơn hàng của Vinh, ta cập nhật các MaSP hiện có.
    """
    if csv_path is None:
        csv_path = os.path.join(current_dir, "sanpham_tiki_congnghe.csv")

    if not os.path.exists(csv_path):
        print(f"[!] Không tìm thấy file {csv_path}. Đang tiến hành tải từ Tiki...")
        df = tai_san_pham_tiki()
    else:
        df = pd.read_csv(csv_path, encoding="utf-8-sig")

    print(f"[*] Đang chuẩn bị cập nhật {len(df)} sản phẩm vào bảng SanPham...")
    conn = get_connection(autocommit=False)
    cursor = conn.cursor()

    try:
        # Tạm tắt trigger ghi lịch sử giá và cảnh báo kho để cập nhật nhanh
        cursor.execute("DISABLE TRIGGER trg_SanPham_LichSuGia ON SanPham;")
        cursor.execute("DISABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;")

        # Cập nhật tên danh mục đầu tiên thành danh mục thực tế
        unique_cats = df["TenDanhMuc"].unique().tolist()
        for idx, cat_name in enumerate(unique_cats, start=1):
            cursor.execute(
                "UPDATE DanhMuc SET TenDanhMuc = ? WHERE MaDanhMuc = ?",
                (cat_name, idx)
            )

        # Lấy danh sách MaSP hiện có trong DB
        cursor.execute("SELECT MaSP FROM SanPham ORDER BY MaSP")
        db_masp = [r[0] for r in cursor.fetchall()]

        # Cập nhật tên và mô tả sản phẩm thật từ Tiki vào các MaSP đầu tiên
        update_data = []
        for i, row in df.iterrows():
            if i >= len(db_masp):
                break
            ma_sp = db_masp[i]
            ten_sp = str(row["TenSP"])
            mo_ta = str(row["MoTa"])
            gia = int(row["Gia"]) if row["Gia"] > 0 else 500000
            update_data.append((ten_sp, mo_ta, gia, ma_sp))

        cursor.fast_executemany = True
        sql_update = "UPDATE SanPham SET TenSP = ?, MoTa = ?, Gia = ? WHERE MaSP = ?"
        cursor.executemany(sql_update, update_data)

        # Bật lại trigger
        cursor.execute("ENABLE TRIGGER trg_SanPham_LichSuGia ON SanPham;")
        cursor.execute("ENABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;")

        conn.commit()
        print(f"[+] Cập nhật thành công {len(update_data)} sản phẩm công nghệ thật vào bảng SanPham!")

    except Exception as e:
        conn.rollback()
        cursor.execute("ENABLE TRIGGER trg_SanPham_LichSuGia ON SanPham;")
        cursor.execute("ENABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;")
        print(f"[-] Lỗi cập nhật: {e}", file=sys.stderr)
        raise
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    tai_san_pham_tiki()
    cap_nhat_database()

