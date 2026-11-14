"""
data/tai_du_lieu_tiki.py
Tải danh mục sản phẩm đồ công nghệ thực tế từ sàn thương mại điện tử Tiki (Cách C).
Lưu kết quả ra file CSV: data/sanpham_tiki_congnghe.csv
Sau đó cập nhật vào bảng DanhMuc và SanPham trong cơ sở dữ liệu ShopDB.

QUAN TRỌNG:
  - File CSV đã được commit sẵn vào repo.
  - Chỉ chạy tai_san_pham_tiki() khi cần làm mới dữ liệu (mỗi lần gọi ~144 request API Tiki).
  - Thành viên khác chỉ cần chạy cap_nhat_database() đọc từ CSV có sẵn.
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

    KHÔNG tự động gọi tai_san_pham_tiki() — để tránh gọi ~144 request API Tiki mỗi lần.
    File CSV đã được commit sẵn trong repo. Nếu chưa có, hãy chạy tai_san_pham_tiki() thủ công.
    """
    if csv_path is None:
        csv_path = os.path.join(current_dir, "sanpham_tiki_congnghe.csv")

    if not os.path.exists(csv_path):
        raise FileNotFoundError(
            f"[!] Không tìm thấy file '{csv_path}'.\n"
            "    Hãy chạy: python data/tai_du_lieu_tiki.py --fetch\n"
            "    hoặc tải file CSV từ repo về thư mục data/."
        )

    df = pd.read_csv(csv_path, encoding="utf-8-sig")

    # --- Kiểm tra chất lượng dữ liệu ---
    # Lọc bỏ sản phẩm có mô tả kiểu "SP demo" (dữ liệu giả, không phải dữ liệu Tiki thực)
    mo_ta_demo = df["MoTa"].str.lower().str.startswith("sp demo")
    n_demo = mo_ta_demo.sum()
    if n_demo > 0:
        print(f"[!] Phát hiện {n_demo} sản phẩm có mô tả 'SP demo...' — bỏ qua, chỉ nạp dữ liệu Tiki thực.")
        df = df[~mo_ta_demo].reset_index(drop=True)

    print(f"[*] Đang chuẩn bị cập nhật {len(df)} sản phẩm vào bảng SanPham...")
    conn = get_connection(autocommit=False)
    cursor = conn.cursor()

    try:
        # Tạm tắt trigger ghi lịch sử giá và cảnh báo kho để cập nhật nhanh
        cursor.execute("DISABLE TRIGGER trg_SanPham_LichSuGia ON SanPham;")
        cursor.execute("DISABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;")

        # --- FIX: Cập nhật danh mục theo TenDanhMuc từ CSV, không dùng idx 1,2,3,4 ---
        # Lấy mapping TenDanhMuc hiện có trong DB
        cursor.execute("SELECT MaDanhMuc, TenDanhMuc FROM DanhMuc ORDER BY MaDanhMuc")
        db_danhmuc = {row[1]: row[0] for row in cursor.fetchall()}

        # Danh mục thực tế từ CSV ánh xạ theo thứ tự xuất hiện
        unique_cats = df["TenDanhMuc"].unique().tolist()
        # Lấy MaDanhMuc hiện có theo thứ tự để gán 1-1 với tên mới
        cursor.execute("SELECT MaDanhMuc FROM DanhMuc ORDER BY MaDanhMuc")
        db_madanhmuc_list = [r[0] for r in cursor.fetchall()]

        cat_to_madanhmuc = {}
        for idx, cat_name in enumerate(unique_cats):
            if idx < len(db_madanhmuc_list):
                ma = db_madanhmuc_list[idx]
                cursor.execute(
                    "UPDATE DanhMuc SET TenDanhMuc = ? WHERE MaDanhMuc = ?",
                    (cat_name, ma)
                )
                cat_to_madanhmuc[cat_name] = ma

        print(f"[*] Đã cập nhật {len(cat_to_madanhmuc)} danh mục: {list(cat_to_madanhmuc.keys())}")

        # Lấy danh sách MaSP hiện có trong DB
        cursor.execute("SELECT MaSP FROM SanPham ORDER BY MaSP")
        db_masp = [r[0] for r in cursor.fetchall()]

        # Cập nhật tên, mô tả, giá, danh mục theo đúng danh mục từ CSV
        update_data = []
        for i, row in df.iterrows():
            if i >= len(db_masp):
                break
            ma_sp = db_masp[i]
            ten_sp = str(row["TenSP"])
            mo_ta = str(row["MoTa"])
            gia = int(row["Gia"]) if row["Gia"] > 0 else 500000
            # Lấy MaDanhMuc đúng theo tên danh mục của sản phẩm
            ma_danhmuc = cat_to_madanhmuc.get(row["TenDanhMuc"])
            update_data.append((ten_sp, mo_ta, gia, ma_danhmuc, ma_sp))

        cursor.fast_executemany = True
        sql_update = "UPDATE SanPham SET TenSP = ?, MoTa = ?, Gia = ?, MaDanhMuc = ? WHERE MaSP = ?"
        cursor.executemany(sql_update, update_data)

        # Bật lại trigger
        cursor.execute("ENABLE TRIGGER trg_SanPham_LichSuGia ON SanPham;")
        cursor.execute("ENABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;")

        conn.commit()
        print(f"[+] Cập nhật thành công {len(update_data)} sản phẩm công nghệ thật vào bảng SanPham!")

    except Exception as e:
        conn.rollback()
        # Bật lại trigger trong trường hợp lỗi
        try:
            cursor.execute("ENABLE TRIGGER trg_SanPham_LichSuGia ON SanPham;")
            cursor.execute("ENABLE TRIGGER trg_SanPham_CanhBaoKho ON SanPham;")
            conn.commit()
        except Exception:
            pass
        print(f"[-] Lỗi cập nhật: {e}", file=sys.stderr)
        raise
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Nạp dữ liệu sản phẩm Tiki vào ShopDB")
    parser.add_argument(
        "--fetch", action="store_true",
        help="Tải lại dữ liệu từ API Tiki (~144 request). Mặc định chỉ đọc CSV có sẵn."
    )
    args = parser.parse_args()

    if args.fetch:
        print("[*] Chế độ --fetch: Đang tải dữ liệu mới từ API Tiki...")
        tai_san_pham_tiki()
    cap_nhat_database()

