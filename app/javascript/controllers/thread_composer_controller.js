import { Controller } from "@hotwired/stimulus"

// Lightweight composer for the thread panel. Deliberately does NOT reuse
// composer_controller, which optimistically inserts a pending message into the
// MAIN room timeline (#message-area) -- a thread reply must never touch that
// timeline. Here we just generate a client_message_id, submit, and clear the
// editor. The reply is delivered back into the open panel live via the
// per-thread Turbo broadcast, so no optimistic insert is needed.
export default class extends Controller {
  static targets = ["text", "clientid"]

  submit(event) {
    // Stamp a client id so the message has a stable identity, mirroring the main
    // composer. The server also backfills one if blank, so this is best-effort.
    if (this.hasClientidTarget && !this.clientidTarget.value) {
      this.clientidTarget.value = this.#generateClientId()
    }
  }

  submitByKeyboard(event) {
    const plainEnter = event.keyCode === 13 && !event.shiftKey && !event.isComposing
    const metaEnter = event.key === "Enter" && (event.metaKey || event.ctrlKey)

    if ((plainEnter || metaEnter) && !this.#usingTouchDevice && this.#hasContent) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }

  submitEnd(event) {
    if (event.detail.success) {
      this.#reset()
    }
  }

  #reset() {
    if (this.hasTextTarget) this.textTarget.value = ""
    if (this.hasClientidTarget) this.clientidTarget.value = ""
  }

  get #hasContent() {
    return this.hasTextTarget && this.textTarget.textContent.trim().length > 0
  }

  get #usingTouchDevice() {
    return "ontouchstart" in window || navigator.maxTouchPoints > 0 || navigator.msMaxTouchPoints > 0
  }

  #generateClientId() {
    return Math.random().toString(36).slice(2)
  }
}
