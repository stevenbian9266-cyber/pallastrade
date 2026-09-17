import { Controller } from '@hotwired/stimulus'

/**
 * Acceptance audit endpoint (PRD-20260916-catalog-ai-acceptance-audit).
 * Fixed rather than a Stimulus value: the admin mount point is fixed, and this
 * keeps the five assistant panels from each carrying another data attribute.
 */
const ACCEPTANCE_ENDPOINT = '/admin/ai/acceptances'

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
    // `edited before save`（PRD-20260917-catalog-ai-edited-before-save）：
    // Accept 只把草稿写进表单（AI 绝不直接落库），真正保存是商家另一次动作。
    // “原样保留”和“改写成能用的东西”是两个完全不同的信号 —— 只有后者说明 AI 输出其实不好用。
    this.acceptedDraft = null
    this.acceptedRunId = null
    this.form = this.element.closest('form')
    this.boundBeforeSubmit = this.beforeSubmit.bind(this)
    this.form?.addEventListener('submit', this.boundBeforeSubmit)
    this.renderIdle()
  }

  disconnect() {
    this.form?.removeEventListener('submit', this.boundBeforeSubmit)
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

    const runId = this.pending.run_id
    const written = []

    if (this.kindValue === 'seo') {
      written.push(this.titleFieldTarget, this.metaDescriptionFieldTarget)
      this.writeValue(this.titleFieldTarget, this.pending.meta_title)
      this.writeValue(this.metaDescriptionFieldTarget, this.pending.meta_description)
    } else if (this.kindValue === 'translation') {
      written.push(...this.translationInputs(this.pending.translations))
      this.acceptTranslation(this.pending.translations)
    } else {
      written.push(this.fieldTarget)
      this.writeValue(this.fieldTarget, this.pending.text)
    }

    this.pending = null
    this.hidePreview()
    this.renderStatus(this.label('Accepted'))
    this.reportAcceptance(runId, 'accepted')
    // 快照必须在**写值之后**取，否则记的是写入前的表单值，每次都会误报 edited。
    this.captureDraft(runId, written)
  }

  /**
   * 记住“刚刚写进去的到底是什么”。保存前用它做**值比较**（不是“表单被碰过吗”）——
   * 后者会把商家改了别的字段也当成编辑，误报。
   */
  captureDraft(runId, inputs) {
    const fields = inputs.filter(Boolean).filter(input => input.name)
    if (!runId || fields.length === 0) return

    this.acceptedRunId = runId
    this.acceptedDraft = fields.map(input => [input.name, input.value])
  }

  /**
   * 保存前比对快照与当前值；**只报一次**，报后立即清空（重复提交不得重复上报）。
   * 找不到对应 input（字段被移除）也算被编辑过 —— 草稿确实没原样留下。
   */
  beforeSubmit() {
    if (!this.acceptedDraft) return

    const changed = this.acceptedDraft.some(([name, value]) => {
      const input = this.form?.querySelector(`[name="${CSS.escape(name)}"]`)
      return input ? input.value !== value : true
    })

    const runId = this.acceptedRunId
    this.acceptedDraft = null
    this.acceptedRunId = null

    if (changed) this.reportAcceptance(runId, 'edited')
  }

  /** @return {Element[]} 翻译抽屉里被写入的那几个 input */
  translationInputs(translations) {
    return Object.keys(translations || {}).map(field => {
      const row = this.element.querySelector(`[data-ai-translation-row="${field}"]`)
      return row?.querySelector('input, textarea')
    })
  }

  discard(event) {
    event.preventDefault()
    const runId = this.pending?.run_id

    this.pending = null
    this.hidePreview()
    this.renderIdle()
    this.reportAcceptance(runId, 'discarded')
  }

  /**
   * Acceptance audit (PRD-20260916-catalog-ai-acceptance-audit): tell the server
   * what the merchant did with the draft — without this, "is the AI draft
   * actually used?" has no answer.
   *
   * Fire-and-forget on purpose: a failed report must never change what the
   * merchant sees (the form write and the status label already happened).
   */
  async reportAcceptance(runId, state) {
    if (!runId) return

    try {
      await fetch(ACCEPTANCE_ENDPOINT, {
        method: 'POST',
        credentials: 'same-origin',
        // `keepalive`：Turbo 提交会接管并跳转，普通 fetch 会在导航中被中断 ——
        // 而“采纳后被编辑”恰好发生在提交那一刻，丢了就永远统计不到。
        keepalive: true,
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-Token': this.csrfToken()
        },
        body: JSON.stringify({ run_id: runId, state })
      })
    } catch (_error) {
      // Observability data must never break the merchant's flow.
    }
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
