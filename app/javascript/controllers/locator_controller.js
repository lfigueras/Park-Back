import { Controller } from "@hotwired/stimulus"

// Captures the browser's current GPS position on the "Save Parking Location"
// screen, fills the hidden form fields, shows accuracy, and previews the spot
// on a small Leaflet map.
export default class extends Controller {
  static targets = [
    "latitude", "longitude", "accuracy",
    "status", "accuracyText", "submit", "map", "retry", "hint"
  ]

  connect() {
    this.map = null
    this.marker = null
    this.locationReady = false
    this.locate()
    this.refreshSubmit()
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  locate() {
    if (!("geolocation" in navigator)) {
      this.fail("Your browser doesn't support location services.")
      return
    }

    this.setStatus("Getting your location…", "pending")
    if (this.hasRetryTarget) this.retryTarget.classList.add("hidden")
    this.locationReady = false
    this.refreshSubmit()

    navigator.geolocation.getCurrentPosition(
      (pos) => this.success(pos),
      (err) => this.fail(this.messageFor(err)),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    )
  }

  success(position) {
    const { latitude, longitude, accuracy } = position.coords

    this.latitudeTarget.value = latitude
    this.longitudeTarget.value = longitude
    if (this.hasAccuracyTarget) this.accuracyTarget.value = Math.round(accuracy)

    this.setStatus("Location locked in", "ok")
    if (this.hasAccuracyTextTarget) {
      this.accuracyTextTarget.textContent = `±${Math.round(accuracy)} m accuracy`
    }
    this.locationReady = true
    this.refreshSubmit()
    if (this.hasRetryTarget) this.retryTarget.classList.remove("hidden")

    this.renderMap(latitude, longitude)
  }

  fail(message) {
    this.setStatus(message, "error")
    if (this.hasRetryTarget) this.retryTarget.classList.remove("hidden")
    this.locationReady = false
    this.refreshSubmit()
  }

  // Enable saving only once we have a GPS fix AND at least one detail filled.
  refreshSubmit() {
    const ready = this.locationReady && this.detailsFilled()
    if (this.hasSubmitTarget) this.submitTarget.disabled = !ready
    if (this.hasHintTarget) this.hintTarget.classList.toggle("hidden", !this.locationReady || ready)
  }

  detailsFilled() {
    const textInputs = this.element.querySelectorAll(
      "input[type=text], input:not([type]), textarea"
    )
    for (const input of textInputs) {
      if (input.value.trim() !== "") return true
    }
    const file = this.element.querySelector("input[type=file]")
    return !!(file && file.files && file.files.length > 0)
  }

  renderMap(lat, lng) {
    if (!this.hasMapTarget || typeof L === "undefined") return

    if (!this.map) {
      this.mapTarget.classList.remove("hidden")
      this.map = L.map(this.mapTarget, { zoomControl: false, attributionControl: false })
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19
      }).addTo(this.map)
    }

    this.map.setView([lat, lng], 18)
    if (this.marker) {
      this.marker.setLatLng([lat, lng])
    } else {
      this.marker = L.marker([lat, lng]).addTo(this.map)
    }
    // Leaflet needs a nudge when its container becomes visible.
    setTimeout(() => this.map.invalidateSize(), 150)
  }

  setStatus(text, state) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.dataset.state = state
  }

  messageFor(err) {
    switch (err.code) {
      case err.PERMISSION_DENIED:
        return "Location permission denied. Enable it to save your spot."
      case err.POSITION_UNAVAILABLE:
        return "Location unavailable right now. Try again."
      case err.TIMEOUT:
        return "Timed out getting your location. Try again."
      default:
        return "Couldn't get your location. Try again."
    }
  }
}
