import { Controller } from "@hotwired/stimulus"

// Reveals / hides the thread panel. The triggering links also carry
// data-turbo-frame="thread-panel", so Turbo loads the thread view into the
// inner frame; this controller only toggles the panel's visibility. It lives on
// the #thread-panel-container element; open/close actions fired from links and
// from the close button (a descendant of the loaded frame) bubble up to it.
export default class extends Controller {
  static targets = ["frame"]
  static classes = ["open"]

  connect() {
    // Close the panel on Escape while it is open.
    this.boundKeydown = this.#handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  open() {
    this.element.hidden = false
    if (this.hasOpenClass) this.element.classList.add(this.openClass)
  }

  close(event) {
    if (event) event.preventDefault()
    this.element.hidden = true
    if (this.hasOpenClass) this.element.classList.remove(this.openClass)
    // Clear the frame so a subsequent open always fetches fresh content and the
    // stale thread does not flash before the new one loads.
    if (this.hasFrameTarget) this.frameTarget.innerHTML = ""
  }

  #handleKeydown(event) {
    if (event.key === "Escape" && !this.element.hidden) {
      this.close()
    }
  }
}
