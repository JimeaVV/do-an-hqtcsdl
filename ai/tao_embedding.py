"""
ai/tao_embedding.py
Phụ trách: Lợi
Mô tả: Đọc danh sách sản phẩm từ bảng SanPham, ghép TenSP và MoTa,
sử dụng SentenceTransformer model "paraphrase-multilingual-MiniLM-L12-v2"
để tạo vector embedding (dạng float32 normalized), sau đó lưu vào bảng SanPham_Embedding.
"""

import sys
import numpy as np
from sentence_transformers import SentenceTransformer
from db_helper import get_connection

MODEL_NAME = "paraphrase-multilingual-MiniLM-L12-v2"

def tao_va_luu_embedding(batch_size=256):
    """
    Đọc tất cả sản phẩm chưa bị xóa (DaXoa = 0), mã hóa thành vector và lưu vào bảng SanPham_Embedding.
    """
    print(f"[*] Đang tải mô hình: {MODEL_NAME}...")
    model = SentenceTransformer(MODEL_NAME)

    print("[*] Đang đọc danh sách sản phẩm từ bảng SanPham...")
    conn = get_connection(autocommit=False)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT MaSP, TenSP, MoTa FROM SanPham WHERE DaXoa = 0 ORDER BY MaSP")
        rows = cursor.fetchall()
        if not rows:
            print("[!] Không tìm thấy sản phẩm nào để tạo embedding.")
            return

        ma_sp_list = []
        noi_dung_list = []

        for r in rows:
            ma = r[0]
            ten = r[1] if r[1] else ""
            mota = r[2] if r[2] else ""
            # Ghép tên và mô tả sản phẩm
            van_ban = f"{ten}. {mota}".strip() if mota else ten.strip()
            ma_sp_list.append(int(ma))
            noi_dung_list.append(van_ban)

        tong_so = len(ma_sp_list)
        print(f"[*] Tổng số sản phẩm cần tạo embedding: {tong_so}")

        print("[*] Đang mã hóa vector với mô hình đa ngôn ngữ (normalize_embeddings=True)...")
        vecs = model.encode(
            noi_dung_list,
            batch_size=batch_size,
            show_progress_bar=True,
            normalize_embeddings=True
        ).astype("float32")

        # Chuyển đổi sang dạng (MaSP, bytes)
        gia_tri = [(int(ma), v.tobytes()) for ma, v in zip(ma_sp_list, vecs)]

        print("[*] Đang lưu vector vào bảng SanPham_Embedding...")
        cursor.fast_executemany = True

        sql_merge = """
        MERGE INTO SanPham_Embedding AS target
        USING (VALUES (?, ?)) AS source (MaSP, Vector)
        ON target.MaSP = source.MaSP
        WHEN MATCHED THEN
            UPDATE SET Vector = source.Vector
        WHEN NOT MATCHED THEN
            INSERT (MaSP, Vector) VALUES (source.MaSP, source.Vector);
        """

        # Thực thi theo lô để tối ưu hiệu năng
        chunk_size = 1000
        for i in range(0, len(gia_tri), chunk_size):
            chunk = gia_tri[i:i + chunk_size]
            cursor.executemany(sql_merge, chunk)

        conn.commit()
        print(f"[+] Hoàn tất! Đã lưu thành công {tong_so} vector vào SanPham_Embedding.")

    except Exception as e:
        conn.rollback()
        print(f"[-] Có lỗi xảy ra: {e}", file=sys.stderr)
        raise
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    tao_va_luu_embedding()

