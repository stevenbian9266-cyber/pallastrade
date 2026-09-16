import { Controller } from '@hotwired/stimulus'

/**
 * AI Product Copilot (PRD-20260915-catalog-batch-e1-ai-copilot).
 *
 * Enforces the Generate → Preview → Accept → Save flow from the plan's §7.2
 * safety boundary: the AI response is only ever rendered into the preview, and
 * the form fields change when — and only when — the merchant clicks Accept.
 * Saving stays a separate, explicit action of the regular product form.
 */
export default class extends Controller {
  static targets = ['field', 'titleField', 'metaDescriptionField', 'preview', 'previewBody', 'status']
  static values = {
    endpoint: String,
    productId: String,
    kind: String,
    mode: { type: String, default: 'generate' },
    locale: String,
    issueKey: String
  }

  connect() {
    this.pending = null
    this.busy = false
    this.renderIdle()
  }

  async generate(event) {
    event.preventDefault()
    if (this.busy) return

    this.busy = true
    this.setBusy(true)
    this.renderStatus(this.label('Generating'))

    try {
      const response = await this.request()
      if (!response.ok) {
        this.renderError(response.data?.error?.code)
        return
      }

      this.pending = response.data
      this.renderPreview(response.data)
    } catch (_error) {
      this.renderError('ai_unavailable')
    } finally {
      this.busy = false
      this.setBusy(false)
    }
  }

  accept(event) {
    event.preventDefault()
    if (!this.pending) return

    if (this.kindValue === 'seo') {
      this.writeValue(this.titleFieldTarget, this.pending.meta_title)
      this.writeValue(this.metaDescriptionFieldTarget, this.pending.meta_description)
    } else if (this.kindValue === 'translation') {
      this.acceptTranslation(this.pending.translations)
    } else {
      this.writeValue(this.fieldTarget, this.pending.text)
    }

    this.pending = null
    this.hidePreview()
    this.renderStatus(this.label('Accepted'))
  }

  discard(event) {
    event.preventDefault()
    this.pending = null
    this.hidePreview()
    this.renderIdle()
  }

  /**
   * Writes every translated field into its own row of the translations drawer.
   * The inputs are named "<field>_<normalized locale>" — the same suffix the
   * drawer's own form uses — so the regular drawer save picks the values up.
   */
  acceptTranslation(translations) {
    Object.entries(translations || {}).forEach(([field, value]) => {
      const row = this.element.querySelector(`[data-ai-translation-row="${field}"]`)
      const input = row?.querySelector('input, textarea')
      this.writeValue(input, value)
    })
  }

  async request() {
    const response = await fetch(this.endpointValue, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': this.csrfToken()
      },
      body: JSON.stringify(this.requestBody())
    })

    const data = await response.json().catch(() => ({}))
    return { ok: response.ok, data }
  }

  requestBody() {
    // Catalog Health suggestions answer for one issue of the worklist.
    if (this.hasIssueKeyValue) return { issue_key: this.issueKeyValue }

    const body = { product_id: this.productIdValue, mode: this.modeValue }
    // Only the translation assistant targets a locale.
    if (this.hasLocaleValue) body.target_locale = this.localeValue
    return body
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
  }

  renderPreview(data) {
    let lines

    if (this.kindValue === 'seo') {
      lines = [
        `${this.label('MetaTitle')}: ${data.meta_title || ''}`,
        `${this.label('MetaDescription')}: ${data.meta_description || ''}`
      ]
    } else if (this.kindValue === 'translation') {
      lines = Object.entries(data.translations || {}).map(([field, value]) => {
        const name = this.label(this.camelize(field)) || field
        return `${name}: ${value}`
      })
    } else if (this.kindValue === 'suggestion') {
      lines = this.suggestionLines(data)
    } else {
      lines = [data.text || '']
    }

    this.previewBodyTarget.textContent = lines.join('\n\n')
    this.previewTarget.classList.remove('hidden')
    this.renderStatus(this.label('Review'))
  }

  camelize(field) {
    return String(field).replace(/(^|_)([a-z])/g, (_match, _prefix, char) => char.toUpperCase())
  }

  /**
   * Catalog Health advice: the summary first, then the ordered steps. A step
   * whose entry is unknown to the server arrives without one — it still shows,
   * just without the surface name.
   */
  suggestionLines(data) {
    const lines = []
    if (data.summary) lines.push(data.summary)

    ;(data.steps || []).forEach((step, index) => {
      const entry = step.entry ? this.label(`Entry:${step.entry}`) : ''
      lines.push(`${index + 1}. ${step.title}${entry ? ` → ${entry}` : ''}`)
    })

    return lines
  }

  renderError(code) {
    this.previewBodyTarget.textContent = ''
    this.previewTarget.classList.add('hidden')
    this.renderStatus(this.label(`Error${code ? `:${code}` : ''}`))
  }

  renderIdle() {
    this.setBusy(false)
    this.renderStatus(this.label('Idle'))
  }

  renderStatus(text) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = text
  }

  label(name) {
    return this.element.dataset[`aiAssist${name}Label`] || ''
  }

  setBusy(busy) {
    this.element.querySelectorAll('[data-ai-assist-role="generate"]').forEach((button) => {
      button.disabled = busy
    })
  }

  hidePreview() {
    this.previewTarget.classList.add('hidden')
  }

  writeValue(element, value) {
    if (!element || value == null) return

    element.value = value
    // Keep TinyMCE (the description editor) and the SEO previews in sync.
    if (window.tinymce && element.id) {
      window.tinymce.get(element.id)?.setContent(value)
    }
    element.dispatchEvent(new Event('input', { bubbles: true }))
  }
}
