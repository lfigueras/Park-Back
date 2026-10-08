import { Controller } from "@hotwired/stimulus"

// Captures the browser's current GPS position on the "Save Parking Location"
// screen, fills the hidden form fields, shows accuracy, and previews the spot
// on a small Leaflet map.
export default class extends Controller {
  static values = { mapPermissionUrl: String, mapsDeclined: Boolean }

  static targets = [
    "latitude", "longitude", "accuracy",
    "status", "accuracyText", "submit", "map", "retry", "hint",
    "gpsUnavailable", "details", "detailsHint", "photoLabel"
  ]

  connect() {
    this.map = null
    this.marker = null
    this.locationReady = this.latitudeTarget.value !== "" && this.longitudeTarget.value !== ""
    this.gpsUnavailable = this.hasGpsUnavailableTarget && this.gpsUnavailableTarget.value === "1"
    this.mapLibraryPromise = null
    if (this.gpsUnavailable) this.setStatus("GPS unavailable. Add a photo or try again.", "error")
    this.refreshSubmit()
    if (!this.mapsDeclinedValue && !this.gpsUnavailable) this.showInitialMap()
  }

  async showInitialMap() {
    try {
      await this.loadMapLibrary()
      if (this.element.isConnected && !this.gpsUnavailable) this.renderMap(20, 0, false)
    } catch {
      if (this.element.isConnected && !this.locationReady && !this.gpsUnavailable) {
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
    this.gpsUnavailable = false
    this.clearCoordinates()
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
    this.gpsUnavailable = false
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
    if (!this.element.isConnected) return
    this.setStatus(message, "error")
    if (this.hasRetryTarget) this.retryTarget.classList.remove("hidden")
    this.locationReady = false
    this.gpsUnavailable = true
    this.clearCoordinates()
    if (this.hasDetailsTarget) this.detailsTarget.open = true
    if (this.map) this.map.remove()
    this.map = null
    this.marker = null
    if (this.hasMapTarget) this.mapTarget.classList.add("hidden")
    this.refreshSubmit()
  }

  clearCoordinates() {
    this.latitudeTarget.value = ""
    this.longitudeTarget.value = ""
    if (this.hasAccuracyTarget) this.accuracyTarget.value = ""
    if (this.hasAccuracyTextTarget) this.accuracyTextTarget.textContent = ""
  }

  refreshSubmit() {
    const file = this.element.querySelector("input[type=file]")
    const photoSelected = !!(file && file.files && file.files.length > 0)
    const ready = this.gpsUnavailable ? photoSelected : this.locationReady && this.detailsFilled()
    if (file) file.required = !!this.gpsUnavailable
    if (this.hasGpsUnavailableTarget) this.gpsUnavailableTarget.value = this.gpsUnavailable ? "1" : "0"
    if (this.hasPhotoLabelTarget) {
      this.photoLabelTarget.textContent = this.gpsUnavailable
        ? "Photo required without GPS (up to 5 MB)"
        : "Photo of the area (up to 5 MB)"
    }
    if (this.hasDetailsHintTarget) this.detailsHintTarget.textContent = this.gpsUnavailable ? "(photo required)" : "(optional)"
    if (this.hasSubmitTarget) this.submitTarget.disabled = !ready
    if (this.hasHintTarget) {
      this.hintTarget.textContent = this.gpsUnavailable
        ? (file ? "GPS is unavailable. Add a photo to save this spot without a map pin." : "GPS and photo uploads are unavailable. Try GPS again.")
        : "Add at least one detail (mall, floor, section, slot, landmark, or photo) before saving."
      this.hintTarget.classList.toggle("hidden", !(this.locationReady || this.gpsUnavailable) || ready)
    }
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
        return "Location permission denied. Add a photo or enable GPS."
      case err.POSITION_UNAVAILABLE:
        return "Location unavailable. Add a photo or try again."
      case err.TIMEOUT:
        return "GPS timed out. Add a photo or try again."
      default:
        return "Couldn't get your location. Add a photo or try again."
    }
  }
}
