"""
ai/test_tim_kiem.py
Kiểm thử tính năng tìm kiếm ngữ nghĩa kết hợp stored procedure sp_SanPham_LayTheoDS.
"""

import json
from tim_kiem import tim_kiem
from db_helper import get_connection

def test_semantic_search():
    conn = get_connection()
    cur = conn.cursor()

    queries = [
        "tai nghe nghe nhạc chống ồn",
        "chuột không dây công thái học êm ái",
        "củ sạc nhanh điện thoại công suất cao",
        "thiết bị xem phim màn hình sắc nét"
    ]

    for q in queries:
        print(f"\n=======================================================")
        print(f"[*] TÌM KIẾM AI: '{q}'")
        print(f"=======================================================")
        top_items = tim_kiem(q, k=3)
        if not top_items:
            print("Không tìm thấy kết quả phù hợp.")
            continue

        ids = [item[0] for item in top_items]
        scores = {item[0]: item[1] for item in top_items}
        json_ids = json.dumps(ids)

        cur.execute("EXEC sp_SanPham_LayTheoDS @DSMaSP = ?", (json_ids,))
        rows = cur.fetchall()

        for r in rows:
            masp, tensp, mota, gia, tonkho, tendm = r[0], r[1], r[2], r[3], r[4], r[5]
            score = scores.get(masp, 0.0)
            print(f"  [Độ tương đồng: {score:.4f}] MaSP: {masp}")
            print(f"  Tên SP: {tensp}")
            print(f"  Danh mục: {tendm} | Giá: {gia:,.0f} đ | Tồn kho: {tonkho}")
            print(f"  Mô tả: {mota[:130]}...")
            print("-" * 50)

    cur.close()
    conn.close()

if __name__ == "__main__":
    test_semantic_search()

