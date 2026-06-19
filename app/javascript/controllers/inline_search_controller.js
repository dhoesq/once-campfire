import { Controller } from "@hotwired/stimulus"

// Sidebar inline (type-ahead) search. Turns the sidebar "Search" row into a live
// search: as the user types (debounced), it fetches a results-only HTML fragment
// from searches#index (format: json -> searches/_results) and drops it into a
// panel below the input. Clicking a result navigates (Turbo) to that message in
// its room and closes the panel.
//
// Design notes:
// - Owns no server state. The fragment is rendered server-side from the existing
//   user-scoped search, so result text is already HTML-escaped; we set it via
//   innerHTML of a *trusted server fragment* (not raw user input).
// - Request sequencing: each fetch carries a monotonically increasing token and
//   uses an AbortController. A slow earlier request can never overwrite a newer
//   query's results.
// - Everything is guarded: a failed fetch shows a quiet empty/error state and
//   never throws.
// - Graceful fallback: the host <form> action is searches_path, so if this
//   controller never connects (JS off / error), Enter still submits server-side.
export default class extends Controller {
  static targets = [ "input", "panel", "results" ]

  #debounceTimer = null
  #abortController = null
  #requestToken = 0
  #activeIndex = -1

  connect() {
    this.#activeIndex = -1
  }

  disconnect() {
    this.#clearDebounce()
    this.#abort()
  }

  // input -> debounce -> fetch
  input() {
    this.#clearDebounce()
    const value = this.#currentQuery()

    if (value.length < 2) {
      this.#abort()
      this.close()
      return
    }

    this.#debounceTimer = setTimeout(() => this.#run(value), 250)
  }

  // keydown handler bound on the form element: Escape closes; Arrow keys move the
  // highlighted result; Enter opens the highlighted result if one is active.
  keydown(event) {
    if (event.key === "Escape") {
      this.close()
      this.inputTarget.blur()
      return
    }

    if (!this.#isOpen()) return

    const results = this.#resultLinks()
    if (results.length === 0) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.#moveSelection(1, results)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.#moveSelection(-1, results)
    } else if (event.key === "Enter") {
      // Only hijack Enter when a result is highlighted; otherwise let the form
      // submit (server-side fallback / full-page search).
      if (this.#activeIndex >= 0 && results[this.#activeIndex]) {
        event.preventDefault()
        results[this.#activeIndex].click()
      }
    }
  }

  // The host form submits to searches_path. When that happens (e.g. Enter with no
  // highlighted result), close the panel so it doesn't linger over the new page.
  submit() {
    this.close()
  }

  // Close when clicking anywhere outside this controller's element.
  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  // Clicking inside the panel: if a result link was clicked, let Turbo navigate
  // (we do not preventDefault) and then close the panel.
  resultClicked(event) {
    if (event.target.closest("[data-inline-search-target='result']")) {
      this.close()
    }
  }

  close() {
    this.#activeIndex = -1
    if (this.hasPanelTarget) {
      this.panelTarget.hidden = true
    }
    if (this.hasResultsTarget) {
      this.resultsTarget.innerHTML = ""
    }
  }

  // --- internals ---

  async #run(query) {
    const token = ++this.#requestToken
    this.#abort()
    this.#abortController = new AbortController()

    this.#showLoading()

    let html = null
    try {
      const url = new URL("/searches.json", window.location.origin)
      url.searchParams.set("q", query)

      const response = await fetch(url, {
        headers: { "Accept": "text/html, application/xhtml+xml" },
        signal: this.#abortController.signal,
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(`Search failed: ${response.status}`)
      html = await response.text()
    } catch (error) {
      if (error && error.name === "AbortError") return // superseded; do nothing
      // Quiet failure: show an empty state, never throw.
      if (token === this.#requestToken) this.#showError()
      return
    }

    // Ignore stale responses (a newer query has since been issued).
    if (token !== this.#requestToken) return

    this.#render(html)
  }

  #render(html) {
    if (!this.hasResultsTarget || !this.hasPanelTarget) return
    // html is a server-rendered, ERB-escaped fragment (searches/_results), not
    // raw user text. Safe to insert.
    this.resultsTarget.innerHTML = html
    this.#activeIndex = -1
    this.#open()
  }

  #showLoading() {
    if (!this.hasResultsTarget || !this.hasPanelTarget) return
    this.resultsTarget.innerHTML = '<div class="inline-search__loading">Searching…</div>'
    this.#open()
  }

  #showError() {
    if (!this.hasResultsTarget || !this.hasPanelTarget) return
    this.resultsTarget.innerHTML = '<div class="inline-search__empty">No results</div>'
    this.#open()
  }

  #open() {
    this.panelTarget.hidden = false
  }

  #isOpen() {
    return this.hasPanelTarget && !this.panelTarget.hidden
  }

  #resultLinks() {
    if (!this.hasResultsTarget) return []
    return Array.from(this.resultsTarget.querySelectorAll("[data-inline-search-target='result']"))
  }

  #moveSelection(delta, results) {
    const next = this.#activeIndex + delta
    if (next < 0) {
      this.#activeIndex = results.length - 1
    } else if (next >= results.length) {
      this.#activeIndex = 0
    } else {
      this.#activeIndex = next
    }

    results.forEach((el, i) => {
      el.classList.toggle("inline-search__result--active", i === this.#activeIndex)
    })

    const active = results[this.#activeIndex]
    if (active && typeof active.scrollIntoView === "function") {
      active.scrollIntoView({ block: "nearest" })
    }
  }

  #currentQuery() {
    return this.hasInputTarget ? this.inputTarget.value.trim() : ""
  }

  #clearDebounce() {
    if (this.#debounceTimer) {
      clearTimeout(this.#debounceTimer)
      this.#debounceTimer = null
    }
  }

  #abort() {
    if (this.#abortController) {
      this.#abortController.abort()
      this.#abortController = null
    }
  }
}
