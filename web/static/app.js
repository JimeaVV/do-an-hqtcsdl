// Hộp thoại xác nhận dùng chung: form nào có data-xac-nhan sẽ hỏi lại trước khi gửi.
document.addEventListener("DOMContentLoaded", () => {
  const hop = document.getElementById("hopXacNhan");
  if (!hop) return;
  const modal = new bootstrap.Modal(hop);
  let formCho = null;

  document.querySelectorAll("form[data-xac-nhan]").forEach((f) => {
    f.addEventListener("submit", (e) => {
      if (f.dataset.daXacNhan === "1") return;
      e.preventDefault();
      formCho = f;
      hop.querySelector("#hopXacNhanTieuDe").textContent = f.dataset.nut ? f.dataset.nut + "?" : "Xác nhận";
      hop.querySelector(".noi-dung-hoi").textContent = f.dataset.xacNhan;
      hop.querySelector(".nut-dong-y").textContent = f.dataset.nut || "Đồng ý";
      modal.show();
    });
  });

  hop.querySelector(".nut-dong-y").addEventListener("click", () => {
    if (!formCho) return;
    formCho.dataset.daXacNhan = "1";
    modal.hide();
    formCho.submit();
  });

  // Nút gửi form hiện trạng thái đang xử lý, tránh bấm hai lần
  document.querySelectorAll("form[data-dang-xu-ly]").forEach((f) => {
    f.addEventListener("submit", () => {
      const nut = f.querySelector("button[type=submit], button:not([type])");
      if (nut) { nut.disabled = true; nut.textContent = f.dataset.dangXuLy; }
    });
  });
});

window.dinhDangTien = (v) => new Intl.NumberFormat("vi-VN").format(Math.round(v)) + " ₫";
window.dinhDangTy = (v) => (v / 1e9).toLocaleString("vi-VN", { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + " tỷ";

// Biểu đồ: chữ và màu lấy theo style.css, tắt hiệu ứng khi người dùng chọn giảm chuyển động
if (window.Chart) {
  Chart.defaults.font.family = "'Be Vietnam Pro', system-ui, sans-serif";
  Chart.defaults.font.size = 14;
  Chart.defaults.color = "#45554E";
  Chart.defaults.borderColor = "#E8EDE9";
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) Chart.defaults.animation = false;
}
