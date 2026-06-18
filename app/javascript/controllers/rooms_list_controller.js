import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { ignoringBriefDisconnects } from "helpers/dom_helpers"

export default class extends Controller {
  static targets = [ "room" ]
  static classes = [ "unread" ]

  #disconnected = true

  async connect() {
    this.markActive()

    this.channel ??= await cable.subscribeTo({ channel: "UnreadRoomsChannel" }, {
      connected: this.#channelConnected.bind(this),
      disconnected: this.#channelDisconnected.bind(this),
      received: this.#unread.bind(this)
    })
  }

  // Highlight the sidebar entry for the room currently open. The sidebar is a
  // permanent Turbo frame, so this is re-run on each navigation via a
  // turbo:load action wired in the sidebar frame.
  markActive() {
    const currentRoomId = Current.room?.id

    this.roomTargets.forEach(roomTarget => {
      roomTarget.classList.toggle("room--active", roomTarget.dataset.roomId == currentRoomId)
    })
  }

  disconnect() {
    ignoringBriefDisconnects(this.element, () => {
      this.channel?.unsubscribe()
      this.channel = null
    })
  }

  loaded() {
    this.markActive()
    this.read({ detail: { roomId: Current.room.id } })
  }

  read({ detail: { roomId } }) {
    const room = this.#findRoomTarget(roomId)

    if (room) {
      room.classList.remove(this.unreadClass)
      this.dispatch("read", { detail: { targetId: roomId } })
    }
  }

  #channelConnected() {
    if (this.#disconnected) {
      this.#disconnected = false
      this.element.reload()
    }
  }

  #channelDisconnected() {
    this.#disconnected = true
  }

  #unread({ roomId }) {
    const unreadRoom = this.#findRoomTarget(roomId)

    if (unreadRoom) {
      if (Current.room.id != roomId) {
        unreadRoom.classList.add(this.unreadClass)
      }

      this.dispatch("unread", { detail: { targetId: unreadRoom.id } })
    }
  }

  #findRoomTarget(roomId) {
    return this.roomTargets.find(roomTarget => roomTarget.dataset.roomId == roomId)
  }
}
