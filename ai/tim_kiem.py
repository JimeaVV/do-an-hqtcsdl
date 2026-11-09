"""
ai/tim_kiem.py
Phụ trách: Lợi
Bàn giao cho Giang:
Hàm: tim_kiem(cau_hoi, k=10)
Trả về: Danh sách (mã sản phẩm, điểm): [(int, float), ...]

Mô tả:
- Tải mô hình SentenceTransformer và đọc toàn bộ vector từ SanPham_Embedding vào bộ nhớ (RAM).
- Khi nhận câu hỏi truy vấn, tính cosine similarity (dot product vì vector đã được normalize)
  giữa vector câu hỏi và vector sản phẩm.
- Trả về top k mã sản phẩm có độ tương đồng ngữ nghĩa cao nhất.
"""

import sys
import os
import numpy as np
from sentence_transformers import SentenceTransformer

# Đảm bảo import được db_helper dù chạy từ thư mục gốc hay bên trong ai/
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from db_helper import get_connection

MODEL_NAME = "paraphrase-multilingual-MiniLM-L12-v2"

# Biến toàn cục cache trong RAM
_model = None
_ma_sp = None       # np.array chứa các MaSP
_vecs = None        # ma trận 2D chứa vector nhị phân float32

def _khoi_tao_model():
    """Khởi tạo mô hình AI nếu chưa có."""
    global _model
    if _model is None:
        print(f"[*] Đang nạp mô hình tìm kiếm: {MODEL_NAME}...")
        _model = SentenceTransformer(MODEL_NAME)
    return _model

def nap_vector():
    """
    Đọc tất cả vector từ bảng SanPham_Embedding và nạp vào bộ nhớ RAM.
    Có thể gọi lại hàm này khi database vừa cập nhật embedding mới.
    """
    global _ma_sp, _vecs
    _khoi_tao_model()

    print("[*] Đang nạp vector sản phẩm từ SanPham_Embedding vào bộ nhớ...")
    conn = get_connection(autocommit=True)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT MaSP, Vector FROM SanPham_Embedding ORDER BY MaSP")
        rows = cursor.fetchall()

        if not rows:
            print("[!] Cảnh báo: Bảng SanPham_Embedding chưa có dữ liệu vector.")
            _ma_sp = np.array([], dtype=int)
            _vecs = np.empty((0, 384), dtype=np.float32)
            return

        ma_list = []
        vec_list = []

        for r in rows:
            ma = r[0]
            blob = r[1]
            if blob:
                v = np.frombuffer(blob, dtype="float32")
                ma_list.append(ma)
                vec_list.append(v)

        _ma_sp = np.array(ma_list, dtype=int)
        _vecs = np.vstack(vec_list).astype("float32")
        print(f"[+] Đã nạp thành công {_vecs.shape[0]} vector vào bộ nhớ.")

    except Exception as e:
        print(f"[-] Lỗi khi nạp vector: {e}", file=sys.stderr)
        _ma_sp = np.array([], dtype=int)
        _vecs = np.empty((0, 384), dtype=np.float32)
    finally:
        cursor.close()
        conn.close()

def tim_kiem(cau_hoi, k=10):
    """
    Tìm kiếm ngữ nghĩa sản phẩm theo câu hỏi người dùng.
    
    Tham số:
        cau_hoi (str): Chuỗi tìm kiếm (ví dụ: 'tai nghe chống ồn văn phòng', 'quà tặng bạn bè')
        k (int): Số lượng kết quả cần lấy (mặc định 10)
        
    Trả về:
        List[Tuple[int, float]]: Danh sách cặp (MaSP, điểm_tương_đồng), sắp xếp theo điểm giảm dần.
    """
    global _model, _ma_sp, _vecs

    if _model is None or _vecs is None:
        nap_vector()

    if _vecs is None or len(_vecs) == 0:
        return []

    # 1. Mã hóa câu truy vấn thành vector normalized
    q = _model.encode([cau_hoi], normalize_embeddings=True)[0].astype("float32")

    # 2. Tính độ tương đồng bằng tích vô hướng (dot product)
    diem = _vecs @ q

    # 3. Lấy top k sản phẩm có điểm cao nhất
    so_luong_lay = min(k, len(diem))
    top_indices = np.argsort(-diem)[:so_luong_lay]

    # 4. Trả về danh sách (MaSP, điểm)
    ket_qua = [(int(_ma_sp[i]), float(diem[i])) for i in top_indices]
    return ket_qua

# Tự động nạp khi module được import
if __name__ == "__main__":
    nap_vector()
    test_queries = [
        "quà tặng cho người hay làm việc ở quán cà phê",
        "đồ dùng cho học sinh học online",
        "tai nghe chống ồn"
    ]
    for q in test_queries:
        print(f"\n--- Thử nghiệm tìm kiếm: '{q}' ---")
        kq = tim_kiem(q, k=5)
        for ma, score in kq:
            print(f"  MaSP: {ma:4d} | Điểm tương đồng: {score:.4f}")

