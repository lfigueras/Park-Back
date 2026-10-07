import { Controller } from "@hotwired/stimulus"

// Captures the browser's current GPS position on the "Save Parking Location"
// screen, fills the hidden form fields, shows accuracy, and previews the spot
// on a small Leaflet map.
export default class extends Controller {
  static values = { mapPermissionUrl: String, mapsDeclined: Boolean }

  static targets = [
    "latitude", "longitude", "accuracy",
    "status", "accuracyText", "submit", "map", "retry", "hint"
  ]

  connect() {
    this.map = null
    this.marker = null
    this.locationReady = false
    this.mapLibraryPromise = null
    this.refreshSubmit()
    if (!this.mapsDeclinedValue) this.showInitialMap()
  }

  async showInitialMap() {
    try {
      await this.loadMapLibrary()
      if (this.element.isConnected) this.renderMap(20, 0, false)
    } catch {
      if (this.element.isConnected && !this.locationReady) {
        this.setStatus("Map unavailable right now. You can still use GPS.", "pending")
      }
    }
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

  async success(position) {
    if (!this.element.isConnected) return
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

    if (this.mapsDeclinedValue) return

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(this.mapPermissionUrlValue, {
        method: "PATCH",
        credentials: "same-origin",
        referrerPolicy: "same-origin",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken || "" }
      })
      if (!response.ok) throw new Error("Map permission could not be saved")
      const preferences = await response.json()
      if (!preferences.maps) return
      await this.loadMapLibrary()
      if (this.element.isConnected) this.renderMap(latitude, longitude)
    } catch {
      if (this.element.isConnected) this.setStatus("Location locked in. Map unavailable right now.", "ok")
    }
  }

  loadMapLibrary() {
    if (typeof L !== "undefined") return Promise.resolve()
    if (this.mapLibraryPromise) return this.mapLibraryPromise

    const stylesheetUrl = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
    if (!document.querySelector(`link[href="${stylesheetUrl}"]`)) {
      const stylesheet = document.createElement("link")
      stylesheet.rel = "stylesheet"
      stylesheet.href = stylesheetUrl
      stylesheet.integrity = "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
      stylesheet.crossOrigin = "anonymous"
      stylesheet.referrerPolicy = "no-referrer"
      document.head.append(stylesheet)
    }

    this.mapLibraryPromise = new Promise((resolve, reject) => {
      const scriptUrl = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
      const existing = document.querySelector(`script[src="${scriptUrl}"]`)
      const script = existing || document.createElement("script")
      script.addEventListener("load", resolve, { once: true })
      script.addEventListener("error", () => {
        script.remove()
        this.mapLibraryPromise = null
        reject(new Error("Map library could not load"))
      }, { once: true })
      if (!existing) {
        script.src = scriptUrl
        script.integrity = "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
        script.crossOrigin = "anonymous"
        script.referrerPolicy = "no-referrer"
        document.head.append(script)
      }
    })
    return this.mapLibraryPromise
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

  renderMap(lat, lng, showMarker = true) {
    if (!this.hasMapTarget || typeof L === "undefined") return

    if (!this.map) {
      this.mapTarget.classList.remove("hidden")
      this.map = L.map(this.mapTarget, { zoomControl: false })
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      }).addTo(this.map)
    }

    this.map.setView([lat, lng], showMarker ? 18 : 2)
    if (showMarker) {
      if (this.marker) {
        this.marker.setLatLng([lat, lng])
      } else {
        this.marker = L.marker([lat, lng]).addTo(this.map)
      }
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
