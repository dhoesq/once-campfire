import { Controller } from "@hotwired/stimulus"

// "Remind me" message action. Additive: POSTs a reminder for the current user
// about a specific message to RemindersController. Mirrors scheduled_send in
// shape (presets + custom datetime), but scoped to a message id.
//
// Targets:
//   custom  - the datetime-local <input>
//   status  - inline feedback span
// Values:
//   url       - reminders_path
//   messageId - the message to be reminded about
export default class extends Controller {
  static targets = [ "custom", "status" ]
  static values = { url: String, messageId: Number }

  remind(event) {
    event.preventDefault()
    const remindAt = this.#presetTime(event.params.preset)
    if (remindAt) this.#submit(remindAt)
  }

  remindCustom(event) {
    event.preventDefault()
    const raw = this.hasCustomTarget ? this.customTarget.value : ""
    if (!raw) {
      this.#setStatus("Pick a date and time")
      return
    }
    const when = new Date(raw)
    if (isNaN(when.getTime()) || when.getTime() <= Date.now()) {
      this.#setStatus("Pick a future time")
      return
    }
    this.#submit(when)
  }

  // --- internals ------------------------------------------------------------

  #presetTime(preset) {
    const now = new Date()
    switch (preset) {
      case "in20min": {
        const d = new Date(now)
        d.setMinutes(d.getMinutes() + 20)
        return d
      }
      case "in1hour": {
        const d = new Date(now)
        d.setHours(d.getHours() + 1)
        return d
      }
      case "tomorrow9": {
        const d = new Date(now)
        d.setDate(d.getDate() + 1)
        d.setHours(9, 0, 0, 0)
        return d
      }
      default:
        return null
    }
  }

  async #submit(remindAt) {
    const formData = new FormData()
    formData.append("message_id", this.messageIdValue)
    formData.append("remind_at", remindAt.toISOString())

    this.#setStatus("Setting…")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.#csrfToken, "Accept": "text/vnd.turbo-stream.html, application/json" },
        body: formData
      })

      if (response.ok) {
        this.#setStatus("Reminder set ✓")
        this.#closePopup()
      } else {
        this.#setStatus("Could not set reminder")
      }
    } catch (_error) {
      this.#setStatus("Could not set reminder")
    }
  }

  #closePopup() {
    const details = this.element.closest("details")
    if (details) details.open = false
  }

  #setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  get #csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
