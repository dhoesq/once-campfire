import { Controller } from "@hotwired/stimulus"

// Toggles the starred state of a room/DM membership for the current user.
// Rendered as a span inside the sidebar room link, so it intercepts the click
// to avoid navigating, then POSTs/DELETEs to the room's star resource. The
// server re-renders the sidebar (HTTP response for this tab) and broadcasts the
// update to the user's :rooms stream for other tabs.
export default class extends Controller {
  static values = { url: String, starred: Boolean }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const method = this.starredValue ? "DELETE" : "POST"

    fetch(this.urlValue, {
      method: method,
      headers: {
        "X-CSRF-Token": this.#csrfToken,
        "Accept": "text/vnd.turbo-stream.html, text/html"
      },
      credentials: "same-origin"
    }).then(response => {
      if (response.ok) return response.text()
      throw new Error(`Star toggle failed: ${response.status}`)
    }).then(html => {
      if (html) Turbo.renderStreamMessage(html)
    }).catch(error => {
      console.error(error)
    })
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
