import { Controller } from "@hotwired/stimulus"

// Drag the sidebar's right edge to resize the left column, persisted to
// localStorage. The width is applied as the `--sidebar-width-user` custom
// property on :root (document.documentElement); layout.css reads it via
// `--sidebar-width: var(--sidebar-width-user, var(--sidebar-width-default))`
// under `body.sidebar` on desktop, so it drives `grid-template-columns`.
//
// Desktop only: the handle is hidden under 100ch (where the sidebar goes
// off-canvas), so dragging never interferes with the mobile toggle.
export default class extends Controller {
  static targets = [ "handle" ]

  static MIN = 200
  static MAX = 440
  static KEY = "campfire:sidebarWidth"
  static PROP = "--sidebar-width-user"

  connect() {
    // Restore a persisted width on every connect (the aside re-renders on Turbo
    // navigations, so re-applying here keeps the column stable without flicker).
    this.restore()

    this._onMove = this.move.bind(this)
    this._onUp = this.stop.bind(this)
    this._dragging = false
  }

  disconnect() {
    this.#removeListeners()
    this.#endDrag()
  }

  // Apply the stored width (if any) to :root before paint.
  restore() {
    const stored = this.#storedWidth()
    if (stored != null) {
      document.documentElement.style.setProperty(this.constructor.PROP, `${stored}px`)
    }
  }

  start(event) {
    // Only respond to a primary pointer (left button / touch / pen).
    if (event.button != null && event.button !== 0) return

    event.preventDefault()
    this._dragging = true
    document.body.style.userSelect = "none"
    document.body.style.cursor = "col-resize"

    document.addEventListener("pointermove", this._onMove)
    document.addEventListener("pointerup", this._onUp)
    document.addEventListener("pointercancel", this._onUp)
  }

  move(event) {
    if (!this._dragging) return

    // The sidebar starts at the left viewport edge, so the pointer's clientX is
    // the candidate width. Clamp it to a sane range.
    const width = this.#clamp(event.clientX)
    document.documentElement.style.setProperty(this.constructor.PROP, `${width}px`)
  }

  stop() {
    if (!this._dragging) return

    this.#endDrag()
    this.#removeListeners()
    this.#persist()
  }

  // --- private helpers ---

  #endDrag() {
    this._dragging = false
    document.body.style.userSelect = ""
    document.body.style.cursor = ""
  }

  #removeListeners() {
    document.removeEventListener("pointermove", this._onMove)
    document.removeEventListener("pointerup", this._onUp)
    document.removeEventListener("pointercancel", this._onUp)
  }

  #persist() {
    const current = getComputedStyle(document.documentElement)
      .getPropertyValue(this.constructor.PROP)
      .trim()
    const px = parseInt(current, 10)
    if (Number.isFinite(px)) {
      try {
        localStorage.setItem(this.constructor.KEY, String(px))
      } catch (_e) {
        // localStorage may be unavailable (private mode); ignore.
      }
    }
  }

  #storedWidth() {
    let raw = null
    try {
      raw = localStorage.getItem(this.constructor.KEY)
    } catch (_e) {
      return null
    }
    if (raw == null) return null
    const px = parseInt(raw, 10)
    return Number.isFinite(px) ? this.#clamp(px) : null
  }

  #clamp(value) {
    return Math.min(this.constructor.MAX, Math.max(this.constructor.MIN, Math.round(value)))
  }
}
