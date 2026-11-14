"""
ai/phan_nhom.py
Phụ trách: Lợi
Bàn giao cho Giang:
Hàm: chay_phan_nhom()
Trả về: Ghi kết quả vào database (cột Nhom bảng KhachHang_PhanNhom), trả về dictionary số khách mỗi nhóm.

Mô tả:
1. Gọi stored procedure sp_TinhRFM để cập nhật R, F, M cho tất cả khách hàng có đơn hoàn thành.
2. Đọc bảng KhachHang_PhanNhom (MaKH, R, F, M).
3. Chuẩn hóa đặc trưng: lấy np.log1p sau đó áp dụng StandardScaler (vì M và F chênh lệch giá trị rất lớn).
4. Phân cụm bằng KMeans (mặc định k=4).
5. Phân tích giá trị trung bình R, F, M của từng cụm để gán nhãn có nghĩa nghiệp vụ:
   - VIP: Chi tiêu cao, mua thường xuyên, gần đây có mua
   - Thân thiết: Mua khá nhiều, chi tiêu ổn định
   - Thỉnh thoảng: Mua ít, giá trị đơn nhỏ
   - Sắp rời bỏ: Đã lâu không mua hàng (R lớn)
6. Cập nhật nhãn nhóm vào cột Nhom của KhachHang_PhanNhom.
7. Gọi sp_PhanNhom_ThongKe và trả về kết quả thống kê.
"""

import sys
import os
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

# Đảm bảo import được db_helper
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from db_helper import get_connection

def danh_gia_k(min_k=2, max_k=8):
    """
    Hàm hỗ trợ thử nghiệm chọn k: in ra Inertia (Elbow) và Silhouette score
    để Lợi đưa vào Chương 6 của báo cáo đồ án.
    """
    conn = get_connection(autocommit=True)
    cursor = conn.cursor()
    cursor.execute("EXEC sp_TinhRFM")
    while cursor.nextset():
        pass
    
    cursor.execute("SELECT MaKH, R, F, M FROM KhachHang_PhanNhom")
    rows = cursor.fetchall()
    cursor.close()
    conn.close()

    if not rows or len(rows) < max_k:
        print("[!] Không đủ dữ liệu khách hàng để đánh giá phân cụm.")
        return

    df = pd.DataFrame.from_records(
        [(r[0], r[1], r[2], float(r[3])) for r in rows],
        columns=["MaKH", "R", "F", "M"]
    )

    X = StandardScaler().fit_transform(np.log1p(df[["R", "F", "M"]]))

    print(f"{'k':<5} | {'Inertia':<15} | {'Silhouette Score':<15}")
    print("-" * 40)
    for k in range(min_k, max_k + 1):
        km = KMeans(n_clusters=k, n_init=10, random_state=42).fit(X)
        sample_size = min(10000, len(X))
        s = silhouette_score(X, km.labels_, sample_size=sample_size, random_state=42)
        print(f"{k:<5} | {round(km.inertia_, 2):<15} | {round(s, 4):<15}")

def _gan_ten_nhom(df_clusters, k=4):
    """
    Đặt tên nhóm dựa trên trung bình R, F, M của từng cụm:
    VIP, Thân thiết, Thỉnh thoảng, Sắp rời bỏ.
    """
    # Tính trung bình R, F, M cho mỗi cụm
    summary = df_clusters.groupby("Cluster").agg({
        "R": "mean",
        "F": "mean",
        "M": "mean"
    }).reset_index()

    if k == 4:
        # R là số ngày kể từ lần mua cuối → R LỚN = đã lâu không mua → "Sắp rời bỏ"
        idx_roi_bo = summary["R"].idxmax()
        cluster_roi_bo = summary.loc[idx_roi_bo, "Cluster"]

        # Các cụm còn lại sắp xếp theo M (tiền chi) giảm dần
        con_lai = summary[summary["Cluster"] != cluster_roi_bo].copy()
        con_lai = con_lai.sort_values(by=["M", "F"], ascending=[False, False])

        cl_list = con_lai["Cluster"].tolist()
        ten_nhom_map = {
            cl_list[0]: "VIP",
            cl_list[1]: "Thân thiết",
            cl_list[2]: "Thỉnh thoảng",
            cluster_roi_bo: "Sắp rời bỏ"
        }
    else:
        # Trường hợp k khác 4, đặt tên theo thứ hạng giá trị M
        summary = summary.sort_values(by="M", ascending=False)
        clusters_sorted = summary["Cluster"].tolist()
        ten_nhom_map = {cl: f"Nhóm {i + 1}" for i, cl in enumerate(clusters_sorted)}

    return ten_nhom_map

def chay_phan_nhom(k=4):
    """
    Hàm bàn giao cho Giang gọi từ giao diện Web.
    
    Trả về:
        Dict[str, int]: Thống kê số lượng khách hàng trong từng nhóm.
    """
    print("[*] Đang thực thi sp_TinhRFM...")
    conn = get_connection(autocommit=False)
    cursor = conn.cursor()

    try:
        # 1. Gọi sp_TinhRFM cập nhật R, F, M vào database
        cursor.execute("EXEC sp_TinhRFM")
        conn.commit()

        # 2. Đọc dữ liệu RFM
        cursor.execute("SELECT MaKH, R, F, M FROM KhachHang_PhanNhom")
        rows = cursor.fetchall()

        if not rows:
            print("[!] Bảng KhachHang_PhanNhom chưa có dữ liệu.")
            return {}

        df = pd.DataFrame.from_records(
            [(r[0], r[1], r[2], float(r[3])) for r in rows],
            columns=["MaKH", "R", "F", "M"]
        )

        so_luong_khach = len(df)
        print(f"[*] Số khách hàng cần phân nhóm: {so_luong_khach}")

        if so_luong_khach < k:
            print(f"[!] Số lượng khách ({so_luong_khach}) nhỏ hơn số cụm k={k}.")
            return {}

        # 3. Chuẩn hóa dữ liệu với log1p và StandardScaler
        X = StandardScaler().fit_transform(np.log1p(df[["R", "F", "M"]]))

        # 4. Huấn luyện KMeans
        print(f"[*] Đang chạy K-Means với k={k}...")
        km = KMeans(n_clusters=k, n_init=10, random_state=42)
        df["Cluster"] = km.fit_predict(X)

        # 5. Gán tên nhóm có nghĩa
        ten_nhom_map = _gan_ten_nhom(df, k=k)
        df["Nhom"] = df["Cluster"].map(ten_nhom_map)

        # 6. Cập nhật nhãn nhóm vào database
        print("[*] Đang lưu tên nhóm vào bảng KhachHang_PhanNhom...")
        cursor.fast_executemany = True
        update_data = [(row["Nhom"], int(row["MaKH"])) for _, row in df.iterrows()]

        sql_update = "UPDATE KhachHang_PhanNhom SET Nhom = ? WHERE MaKH = ?"
        chunk_size = 5000
        for i in range(0, len(update_data), chunk_size):
            chunk = update_data[i:i + chunk_size]
            cursor.executemany(sql_update, chunk)

        conn.commit()

        # 7. Lấy thống kê số khách mỗi nhóm
        cursor.execute("EXEC sp_PhanNhom_ThongKe")
        thong_ke_rows = cursor.fetchall()
        ket_qua = {}
        for r in thong_ke_rows:
            nhom = r[0]
            so_khach = r[1]
            ket_qua[nhom] = int(so_khach)

        print("[+] Phân nhóm hoàn tất! Kết quả thống kê:")
        for nhom, count in ket_qua.items():
            print(f"    - {nhom}: {count} khách hàng")

        return ket_qua

    except Exception as e:
        conn.rollback()
        print(f"[-] Lỗi trong quá trình phân nhóm: {e}", file=sys.stderr)
        raise
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    chay_phan_nhom()

