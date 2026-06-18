import { Controller } from "@hotwired/stimulus"
import FileUploader from "models/file_uploader"
import { onNextEventLoopTick, nextFrame } from "helpers/timing_helpers"
import { escapeHTML } from "helpers/dom_helpers"

export default class extends Controller {
  static classes = ["toolbar"]
  static targets = [ "clientid", "fields", "fileList", "text" ]
  static values = { roomId: Number, roomName: String }
  static outlets = [ "messages" ]

  #files = []
  #draftSaveTimeout = null

  connect() {
    this.#restoreDraft()

    if (!this.#usingTouchDevice) {
      onNextEventLoopTick(() => this.textTarget.focus())
    }
  }

  disconnect() {
    // Flush any pending debounced save so a fast room-switch never drops text.
    if (this.#draftSaveTimeout) {
      clearTimeout(this.#draftSaveTimeout)
      this.#draftSaveTimeout = null
      this.#writeDraft()
    }
  }

  // Wired from the editor's trix-change action. Lightly debounced so we are not
  // touching localStorage on every keystroke. Persists text body only; file
  // attachments are intentionally not drafted.
  draftSave() {
    if (this.#draftSaveTimeout) clearTimeout(this.#draftSaveTimeout)
    this.#draftSaveTimeout = setTimeout(() => {
      this.#draftSaveTimeout = null
      this.#writeDraft()
    }, 300)
  }

  submit(event) {
    event.preventDefault()

    if (!this.fieldsTarget.disabled) {
      this.#submitFiles()
      this.#submitMessage()
      this.collapseToolbar()
      this.textTarget.focus()
    }
  }

  submitEnd(event) {
    if (!event.detail.success) {
      this.messagesOutlet.failPendingMessage(this.clientidTarget.value)
    }
  }

  toggleToolbar() {
    this.element.classList.toggle(this.toolbarClass)
    this.textTarget.focus()
  }

  collapseToolbar() {
    this.element.classList.remove(this.toolbarClass)
  }

  replaceMessageContent(content) {
    const editor = this.textTarget.editor

    editor.recordUndoEntry("Format reply")
    editor.setSelectedRange([0, editor.getDocument().toString().length])
    editor.deleteInDirection("forward")
    editor.insertHTML(content)
    editor.setSelectedRange([editor.getDocument().toString().length - 1])
  }

  submitByKeyboard(event) {
    const toolbarVisible = this.element.classList.contains(this.toolbarClass)
    const metaEnter = event.key == "Enter" && (event.metaKey || event.ctrlKey)
    const plainEnter = event.keyCode == 13 && !event.shiftKey && !event.isComposing

    if (!this.#usingTouchDevice && (metaEnter || (plainEnter && !toolbarVisible))) {
      this.submit(event)
    }
  }

  filePicked(event) {
    for (const file of event.target.files) {
      this.#files.push(file)
    }
    event.target.value = null
    this.#updateFileList()
  }

  fileUnpicked(event) {
    this.#files.splice(event.params.index, 1)
    this.#updateFileList()
  }

  pasteFiles(event) {
    if (event.clipboardData.files.length > 0) {
      event.preventDefault()
    }

    for (const file of event.clipboardData.files) {
      this.#files.push(file)
    }

    this.#updateFileList()
  }

  dropFiles({ detail: { files } }) {
    for (const file of files) {
      this.#files.push(file)
    }

    this.#updateFileList()
  }

  preventAttachment(event) {
    event.preventDefault()
  }

  online() {
    this.fieldsTarget.disabled = false
  }

  offline() {
    this.fieldsTarget.disabled = true
  }

  get #usingTouchDevice() {
    return 'ontouchstart' in window || navigator.maxTouchPoints > 0 || navigator.msMaxTouchPoints > 0;
  }

  async #submitMessage() {
    if (this.#validInput()) {
      const clientMessageId = this.#generateClientId()

      await this.messagesOutlet.insertPendingMessage(clientMessageId, this.textTarget)
      await nextFrame()

      this.clientidTarget.value = clientMessageId
      this.element.requestSubmit()
      this.#reset()
    }
  }

  #validInput() {
    return this.textTarget.textContent.trim().length > 0
  }

  async #submitFiles() {
    const files = this.#files

    this.#files = []
    this.#updateFileList()

    for (const file of files) {
      const clientMessageId = this.#generateClientId()
      const uploader = new FileUploader(file, this.element.action, clientMessageId, this.#uploadProgress.bind(this))

      const body = this.#pendingUploadProgress(file.name)
      await this.messagesOutlet.insertPendingMessage(clientMessageId, body)

      const resp = await uploader.upload()

      Turbo.renderStreamMessage(resp)
    }
  }

  #uploadProgress(percent, clientMessageId, file) {
    const body = this.#pendingUploadProgress(file.name, percent)
    this.messagesOutlet.updatePendingMessage(clientMessageId, body)
  }

  #generateClientId() {
    return Math.random().toString(36).slice(2)
  }

  #reset() {
    this.textTarget.value = ""
    // A sent message must never linger as a draft, so clear it at the exact
    // point the editor is cleared after a successful submit.
    this.#clearDraft()
  }

  // --- Per-room drafts (client-side, localStorage; text body only) -----------

  get #draftKey() {
    return `campfire:draft:${this.roomIdValue}`
  }

  // Parses a stored draft value into { name, body }. Backward-compatible: an
  // older plain-string value (or anything that fails JSON.parse / isn't the
  // object shape) is treated as a bare body so legacy drafts still restore.
  #parseDraft(raw) {
    if (raw == null) return null

    try {
      const parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object" && typeof parsed.body === "string") {
        return { name: typeof parsed.name === "string" ? parsed.name : null, body: parsed.body }
      }
      // JSON parsed but not our shape (e.g. a number, array, or a JSON string).
      return { name: null, body: String(raw) }
    } catch (_error) {
      // Not JSON at all: old format stored the raw HTML body as a plain string.
      return { name: null, body: raw }
    }
  }

  #writeDraft() {
    if (!this.hasRoomIdValue) return

    const html = this.textTarget.value

    try {
      if (html && html.trim().length > 0) {
        const record = {
          name: this.hasRoomNameValue ? this.roomNameValue : null,
          body: html,
          updatedAt: Date.now()
        }
        window.localStorage.setItem(this.#draftKey, JSON.stringify(record))
      } else {
        window.localStorage.removeItem(this.#draftKey)
      }
    } catch (_error) {
      // localStorage may be unavailable (private mode, quota). Drafts are a
      // convenience, never required, so fail silently.
    }

    this.#notifyDraftsChanged()
  }

  #restoreDraft() {
    if (!this.hasRoomIdValue) return

    let raw = null
    try {
      raw = window.localStorage.getItem(this.#draftKey)
    } catch (_error) {
      return
    }

    const draft = this.#parseDraft(raw)
    const html = draft?.body

    // Only restore when there is a draft and the editor is empty, so we never
    // clobber content already present (e.g. a forwarded/quoted reply).
    if (html && html.trim().length > 0 && this.textTarget.value.trim().length === 0) {
      this.textTarget.value = html
    }
  }

  #clearDraft() {
    if (this.#draftSaveTimeout) {
      clearTimeout(this.#draftSaveTimeout)
      this.#draftSaveTimeout = null
    }

    if (!this.hasRoomIdValue) return

    try {
      window.localStorage.removeItem(this.#draftKey)
    } catch (_error) {
      // Ignore; see #writeDraft.
    }

    this.#notifyDraftsChanged()
  }

  // Lets the sidebar drafts list refresh without a page reload. Fired whenever a
  // draft is written or cleared. Best-effort: never let it break the composer.
  #notifyDraftsChanged() {
    try {
      window.dispatchEvent(new CustomEvent("campfire:drafts-changed"))
    } catch (_error) {
      // Ignore: drafts list is a convenience, not required.
    }
  }

  #updateFileList() {
    this.#files.sort((a, b) => a.name.localeCompare(b.name))

    const fileNodes = this.#files.map((file, index) => {
      const filename = file.name.split(".").slice(0, -1).join(".")
      const extension = file.name.split(".").pop()

      const node = document.createElement("button")
      node.setAttribute("type","button")
      node.setAttribute("style","gap: 0")
      node.dataset.action = "composer#fileUnpicked"
      node.dataset.composerIndexParam = index
      node.className = "btn btn--plain composer__file txt-normal position-relative unpad flex-column"
      node.innerHTML = file.type.match(/^image\/.*/) ? `<img role="presentation" class="flex-item-no-shrink composer__file-thumbnail" src="${URL.createObjectURL(file)}">` : `<span class="composer__file-thumbnail composer__file-thumbnail--common colorize--black"></span>`
      node.innerHTML += `<span class="pad-inline txt-small flex align-center max-width composer__file-caption"><span class="overflow-ellipsis">${escapeHTML(filename)}.</span><span class="flex-item-no-shrink">${escapeHTML(extension)}</span></span>`

      return node
    })

    this.fileListTarget.replaceChildren(...fileNodes)
  }

  #pendingUploadProgress(filename, percent=0) {
    return `
      <div class="message__pending-upload flex align-center gap" style="--percentage: ${percent}%">
        <div class="composer__file-thumbnail composer__file-thumbnail--common colorize--black borderless flex-item-no-shrink"></div>
        <div>${escapeHTML(filename)} - <span>${percent}%</span></div>
      </div>
    `
  }
}
