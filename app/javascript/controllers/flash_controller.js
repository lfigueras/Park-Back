import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 3000 } }

  connect() {
    this.dismissing = false
    if (this.delayValue > 0) {
      this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
    }
  }

  dismiss() {
    if (this.dismissing) return
    this.dismissing = true
    clearTimeout(this.timeout)
    this.element.classList.add("flash-toast--leaving")
    this.removeTimeout = setTimeout(() => this.element.remove(), 250)
  }

  disconnect() {
    clearTimeout(this.timeout)
    clearTimeout(this.removeTimeout)
  }
}