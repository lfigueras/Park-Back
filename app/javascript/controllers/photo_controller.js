import { Controller } from "@hotwired/stimulus"

// Lets the user either take a new photo (camera) or upload one from their
// gallery, backed by a single file input, with a live thumbnail preview.
export default class extends Controller {
  static targets = ["input", "preview", "image"]

  // Open the camera directly.
  takePhoto() {
    this.inputTarget.setAttribute("capture", "environment")
    this.inputTarget.click()
  }

  // Open the gallery / file picker (no capture hint).
  choose() {
    this.inputTarget.removeAttribute("capture")
    this.inputTarget.click()
  }

  preview() {
    const file = this.inputTarget.files && this.inputTarget.files[0]
    if (!file) return this.hidePreview()

    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(file)
    this.imageTarget.src = this.objectUrl
    this.previewTarget.classList.remove("hidden")
  }

  clear() {
    this.inputTarget.value = ""
    this.hidePreview()
    // Let the locator controller re-check whether a detail is still present.
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  hidePreview() {
    this.previewTarget.classList.add("hidden")
    this.imageTarget.removeAttribute("src")
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
  }

  disconnect() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  }
}
