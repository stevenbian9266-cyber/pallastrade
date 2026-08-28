import { Controller } from "@hotwired/stimulus"

// P6 (2026-08-28)：Admin 手动拆单表单——勾选行项目 → 实时预览拆出数量与小计。
// 每行 checkbox 的 data-total 携带行项目总金额（服务器端渲染）。
export default class extends Controller {
  static targets = ["row", "count", "total", "submit"]

  connect() {
    this.update()
  }

  toggle() {
    this.update()
  }

  toggleAll(event) {
    this.rowTargets.forEach((row) => {
      row.querySelector('input[type="checkbox"]').checked = event.target.checked
    })
    this.update()
  }

  update() {
    const rows = this.rowTargets.filter((row) => {
      const checkbox = row.querySelector('input[type="checkbox"]')
      return checkbox && checkbox.checked
    })

    if (this.hasCountTarget) {
      this.countTarget.textContent = rows.length
    }
    if (this.hasTotalTarget) {
      const sum = rows.reduce((acc, row) => {
        const total = Number(row.dataset.total || 0)
        return acc + total
      }, 0)
      this.totalTarget.textContent = sum.toFixed(2)
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = rows.length === 0
    }
  }
}
