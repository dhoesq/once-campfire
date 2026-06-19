import { Controller } from "@hotwired/stimulus"

// Composer "Schedule send" affordance. This is ADDITIVE and never touches the
// normal send button or composer_controller: it reads the composer's current
// rich-text body out of the trix editor, POSTs it to ScheduledMessagesController,
// and on success clears the editor. The scheduled message does NOT post to the
// timeline now; the in-container sweeper delivers it at deliver_at.
//
// Targets:
//   custom  - the datetime-local <input> for a custom time
//   status  - a small span for inline feedback
// Values:
//   url     - scheduled_messages_path
//   roomId  - the room being composed in
export default class extends Controller {
  static targets = [ "custom", "status" ]
  static values = { url: String, roomId: Number }

  // Quick presets. event.params.preset is one of the keys below.
  schedule(event) {
    event.preventDefault()
    const deliverAt = this.#presetTime(event.params.preset)
    if (deliverAt) this.#submit(deliverAt)
  }

  scheduleCustom(event) {
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
      case "nextmonday9": {
        const d = new Date(now)
        const day = d.getDay() // 0 Sun .. 6 Sat
        // Days until next Monday (always at least 1, so "next" never means today).
        const delta = ((8 - day) % 7) || 7
        d.setDate(d.getDate() + delta)
        d.setHours(9, 0, 0, 0)
        return d
      }
      default:
        return null
    }
  }

  // Read the composer's trix editor body without disturbing it. The editor lives
  // in the same composer form; we locate it by its composer "text" target.
  #composerEditor() {
    const composer = this.element.closest("#composer") || document.getElementById("composer")
    if (!composer) return null
    return composer.querySelector('[data-composer-target="text"]')
  }

  async #submit(deliverAt) {
    const editor = this.#composerEditor()
    if (!editor) {
      this.#setStatus("Composer not found")
      return
    }

    const body = editor.value || ""
    // Mirror the composer's empty-input guard: do nothing on an empty body.
    if (!editor.textContent || editor.textContent.trim().length === 0) {
      this.#setStatus("Write a message first")
      return
    }

    const formData = new FormData()
    formData.append("body", body)
    formData.append("room_id", this.roomIdValue)
    formData.append("deliver_at", deliverAt.toISOString())

    this.#setStatus("Scheduling…")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.#csrfToken, "Accept": "text/vnd.turbo-stream.html, application/json" },
        body: formData
      })

      if (response.ok) {
        this.#clearComposer(editor)
        this.#setStatus("Scheduled ✓")
        this.#closePopup()
      } else {
        this.#setStatus("Could not schedule")
      }
    } catch (_error) {
      this.#setStatus("Could not schedule")
    }
  }

  // Clear the editor through trix's own API so the change is recorded and drafts
  // clear naturally (composer_controller listens to trix-change). We do not call
  // any composer_controller method directly.
  #clearComposer(editor) {
    if (editor.editor) {
      editor.editor.setSelectedRange([ 0, editor.editor.getDocument().toString().length ])
      editor.editor.deleteInDirection("forward")
    } else {
      editor.value = ""
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
