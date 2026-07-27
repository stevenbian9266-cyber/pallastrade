import { Controller } from "@hotwired/stimulus"

// Category cascade controller — 3-level horizontal cascading dropdown
// Data flows via data-children attributes embedded in the HTML,
// avoiding extra API calls. The view pre-loads children IDs on each <option>.
export default class extends Controller {
  static targets = ["level1", "level2", "level3"]

  // Level 1 changed → repopulate level 2, reset level 3
  loadLevel2(event) {
    this.resetSelect(this.level2Target)
    this.resetSelect(this.level3Target)

    const children = this.getChildren(event.target)
    if (children.length === 0) return

    children.forEach(id => {
      const name = this.findCategoryName(id)
      const grandChildren = this.findChildren(id)
      if (name) this.addOption(this.level2Target, id, name, grandChildren)
    })
    this.level2Target.disabled = false
  }

  // Level 2 changed → repopulate level 3
  loadLevel3(event) {
    this.resetSelect(this.level3Target)

    const children = this.getChildren(event.target)
    if (children.length === 0) return

    children.forEach(id => {
      const name = this.findCategoryName(id)
      if (name) this.addOption(this.level3Target, id, name, [])
    })
    this.level3Target.disabled = false
  }

  // Parse data-children JSON from selected option
  getChildren(select) {
    const opt = select.selectedOptions[0]
    if (!opt?.dataset?.children) return []
    try { return JSON.parse(opt.dataset.children) } catch { return [] }
  }

  // Look up category name from pre-loaded name map
  findCategoryName(id) {
    if (!this._nameMap) {
      this._nameMap = {}
      try {
        const el = document.getElementById('category-name-map')
        if (el) this._nameMap = JSON.parse(el.textContent)
      } catch { /* ignore */ }
    }
    return this._nameMap[id] || null
  }

  // Look up children IDs from pre-loaded children map
  findChildren(id) {
    if (!this._childrenMap) {
      this._childrenMap = {}
      try {
        const el = document.getElementById('category-children-map')
        if (el) this._childrenMap = JSON.parse(el.textContent)
      } catch { /* ignore */ }
    }
    return this._childrenMap[id] || []
  }

  resetSelect(select) {
    const placeholder = select.querySelector('option[value=""]')
    const text = placeholder ? placeholder.textContent : ''
    select.innerHTML = placeholder ? `<option value="">${text}</option>` : '<option value=""></option>'
    select.disabled = true
  }

  addOption(select, value, text, children) {
    const opt = document.createElement('option')
    opt.value = value
    opt.textContent = text
    if (children && children.length > 0) {
      opt.dataset.children = JSON.stringify(children)
    }
    select.appendChild(opt)
  }
}
