import { Controller } from "@hotwired/stimulus"

// Renders a Slack-style "Drafts" section in the sidebar. It owns no server
// state: on connect (and whenever the composer fires campfire:drafts-changed)
// it scans localStorage for `campfire:draft:*` keys, parses each draft, and
// renders one row per room that has an unsent draft. The whole section (label
// included) hides when there are no drafts.
//
// Storage shape (written by composer_controller):
//   campfire:draft:<roomId> => { "name": <roomName>, "body": <html>, "updatedAt": <ms> }
// Backward-compatible: an older plain-string value (or any value that doesn't
// parse to our object shape) is treated as { name: null, body: <string> } so a
// pre-upgrade draft still shows up and never throws.
export default class extends Controller {
  static targets = [ "section", "list" ]

  #onDraftsChanged = () => this.render()

  connect() {
    window.addEventListener("campfire:drafts-changed", this.#onDraftsChanged)
    this.render()
  }

  disconnect() {
    window.removeEventListener("campfire:drafts-changed", this.#onDraftsChanged)
  }

  render() {
    let drafts = []
    try {
      drafts = this.#collectDrafts()
    } catch (_error) {
      // localStorage unavailable (private mode, disabled, etc.): render nothing
      // and keep the section hidden. Drafts are a convenience, never required.
      drafts = []
    }

    if (drafts.length === 0) {
      this.#hideSection()
      return
    }

    drafts.sort((a, b) => b.updatedAt - a.updatedAt)
    this.#renderRows(drafts)
    this.#showSection()
  }

  #collectDrafts() {
    const storage = window.localStorage
    const prefix = "campfire:draft:"
    const drafts = []

    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i)
      if (!key || key.indexOf(prefix) !== 0) continue

      const roomId = key.slice(prefix.length)
      if (!roomId) continue

      let raw = null
      try {
        raw = storage.getItem(key)
      } catch (_error) {
        continue
      }

      const parsed = this.#parseDraft(raw)
      // A corrupt or empty-body entry is skipped, not fatal.
      if (!parsed || !parsed.body || parsed.body.trim().length === 0) continue

      drafts.push({
        roomId,
        name: parsed.name,
        snippet: this.#snippet(parsed.body),
        updatedAt: parsed.updatedAt
      })
    }

    return drafts
  }

  // Mirrors composer_controller#parseDraft: tolerate the old plain-string format
  // and any non-conforming JSON. Returns { name, body, updatedAt } or null.
  #parseDraft(raw) {
    if (raw == null) return null

    try {
      const obj = JSON.parse(raw)
      if (obj && typeof obj === "object" && typeof obj.body === "string") {
        return {
          name: typeof obj.name === "string" ? obj.name : null,
          body: obj.body,
          updatedAt: typeof obj.updatedAt === "number" ? obj.updatedAt : 0
        }
      }
      return { name: null, body: String(raw), updatedAt: 0 }
    } catch (_error) {
      return { name: null, body: raw, updatedAt: 0 }
    }
  }

  // Strip HTML tags, collapse whitespace, decode basic entities, truncate ~40.
  #snippet(html) {
    const tmp = document.createElement("div")
    tmp.innerHTML = html
    const text = (tmp.textContent || tmp.innerText || "").replace(/\s+/g, " ").trim()
    if (text.length <= 40) return text
    return text.slice(0, 40).trimEnd() + "…"
  }

  #renderRows(drafts) {
    const rows = drafts.map((draft) => {
      const link = document.createElement("a")
      link.href = "/rooms/" + draft.roomId
      link.className = "draft-row room room--row btn align-center gap txt-nowrap"

      const name = document.createElement("span")
      name.className = "room__name overflow-ellipsis"
      name.textContent = draft.name || "Conversation"

      const snippet = document.createElement("span")
      snippet.className = "draft-row__snippet overflow-ellipsis"
      snippet.textContent = draft.snippet

      link.appendChild(name)
      link.appendChild(snippet)
      return link
    })

    this.listTarget.replaceChildren(...rows)
  }

  #showSection() {
    this.sectionTarget.hidden = false
  }

  #hideSection() {
    this.sectionTarget.hidden = true
    this.listTarget.replaceChildren()
  }
}
