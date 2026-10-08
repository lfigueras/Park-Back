import { Controller } from "@hotwired/stimulus"

// Powers the "Find My Car" screen: draws the saved spot + the user on a Leaflet
// map, and live-updates walking distance, compass direction, and elapsed time.
export default class extends Controller {
  static values = {
    carLat: Number,
    carLng: Number,
    savedAt: String,
    expiresAt: String,
    vehicle: String,
    gpsAvailable: { type: Boolean, default: true }
  }

  static targets = [
    "map", "distance", "distanceUnit", "bearing", "arrow",
    "elapsed", "status", "compassNote"
  ]

  connect() {
    this.watchId = null
    this.heading = null
    this.userMarker = null
    this.userCircle = null
    this.line = null
    this.boundResume = this.refreshPosition.bind(this)

    this.initMap()
    this.startClock()
    this.refreshPosition()
    if (this.hasCoordinates) this.bindCompass()
    document.addEventListener("visibilitychange", this.boundResume)
    window.addEventListener("pageshow", this.boundResume)
  }

  disconnect() {
    if (this.watchId !== null) navigator.geolocation.clearWatch(this.watchId)
    if (this.clock) clearInterval(this.clock)
    if (this.map) this.map.remove()
    window.removeEventListener("deviceorientationabsolute", this.boundOrientation, true)
    window.removeEventListener("deviceorientation", this.boundOrientation, true)
    document.removeEventListener("visibilitychange", this.boundResume)
    window.removeEventListener("pageshow", this.boundResume)
  }

  get car() {
    return [this.carLatValue, this.carLngValue]
  }

  get hasCoordinates() {
    return !this.hasGpsAvailableValue || this.gpsAvailableValue
  }

  // SVG path (Material Symbols) for the saved vehicle's map marker.
  vehiclePath() {
    const paths = {
      car: "M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z",
      motorcycle: "M19.44 9.03L15.41 5H11v2h3.59l2 2H5c-2.8 0-5 2.2-5 5s2.2 5 5 5c2.46 0 4.45-1.69 4.9-4h1.65l2.77-2.77c-.21.54-.32 1.14-.32 1.77 0 2.8 2.2 5 5 5s5-2.2 5-5c0-2.8-2.2-5-5-5h-.56zM7.82 15C7.4 16.15 6.28 17 5 17c-1.63 0-3-1.37-3-3s1.37-3 3-3c1.28 0 2.4.85 2.82 2H5v2h2.82zM19 17c-1.63 0-3-1.37-3-3s1.37-3 3-3 3 1.37 3 3-1.37 3-3 3z",
      bicycle: "M15.5 5.5c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zM5 12c-2.8 0-5 2.2-5 5s2.2 5 5 5 5-2.2 5-5-2.2-5-5-5zm0 8.5c-1.9 0-3.5-1.6-3.5-3.5s1.6-3.5 3.5-3.5 3.5 1.6 3.5 3.5-1.6 3.5-3.5 3.5zm5.8-10l2.4-2.4.8.8c1.3 1.3 3 2.1 5.1 2.1V9c-1.5 0-2.7-.6-3.6-1.5l-1.9-1.9c-.5-.4-1-.6-1.6-.6s-1.1.2-1.4.6L7.8 8.4c-.4.4-.6.9-.6 1.6 0 .6.2 1.1.6 1.4L11 14v5h2v-6.2l-2.2-2.3zM19 12c-2.8 0-5 2.2-5 5s2.2 5 5 5 5-2.2 5-5-2.2-5-5-5zm0 8.5c-1.9 0-3.5-1.6-3.5-3.5s1.6-3.5 3.5-3.5 3.5 1.6 3.5 3.5-1.6 3.5-3.5 3.5z",
      truck: "M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4zM6 18.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm13.5-9l1.96 2.5H17V9.5h2.5zm-1.5 9c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z"
    }
    return paths[this.vehicleValue] || paths.car
  }

  initMap() {
    if (!this.hasCoordinates || !this.hasMapTarget || typeof L === "undefined") return

    this.map = L.map(this.mapTarget, { zoomControl: true })
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)
    this.map.setView(this.car, 18)

    const carIcon = L.divIcon({
      className: "",
      html: `
        <div style="display:grid;place-items:center;width:40px;height:40px;border-radius:9999px;background:#3a5f97;border:2px solid #fff;box-shadow:0 2px 8px rgba(58,95,151,.4)">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="#fff" aria-hidden="true">
            <path d="${this.vehiclePath()}"/>
          </svg>
        </div>`,
      iconSize: [40, 40],
      iconAnchor: [20, 20]
    })
    this.carMarker = L.marker(this.car, { icon: carIcon }).addTo(this.map)
  }

  startClock() {
    this.renderElapsed()
    this.clock = setInterval(() => this.renderElapsed(), 1000)
  }

  renderElapsed() {
    if (!this.hasElapsedTarget || !this.savedAtValue) return
    const saved = new Date(this.savedAtValue)
    let secs = Math.max(0, Math.floor((Date.now() - saved.getTime()) / 1000))

    const h = Math.floor(secs / 3600)
    const m = Math.floor((secs % 3600) / 60)
    const s = secs % 60
    const parts = []
    if (h) parts.push(`${h}h`)
    if (h || m) parts.push(`${m}m`)
    parts.push(`${s}s`)
    this.elapsedTarget.textContent = parts.join(" ")
  }

  refreshPosition() {
    if (document.visibilityState === "hidden") return
    if (this.hasExpiresAtValue && Date.now() >= Date.parse(this.expiresAtValue)) {
      window.location.reload()
      return
    }

    this.renderElapsed()
    if (!this.hasCoordinates) return
    this.heading = null
    this.bearingToCar = null
    if (this.hasDistanceTarget) this.distanceTarget.textContent = "--"
    if (this.hasBearingTarget) this.bearingTarget.textContent = "--"
    if (this.hasArrowTarget) this.arrowTarget.style.visibility = "hidden"
    this.startWatching()
  }

  startWatching() {
    if (this.watchId !== null) {
      navigator.geolocation.clearWatch(this.watchId)
      this.watchId = null
    }
    if (!("geolocation" in navigator)) {
      this.setStatus("Location services unavailable on this device.")
      return
    }
    this.setStatus("Locating you…")
    this.watchId = navigator.geolocation.watchPosition(
      (pos) => this.onPosition(pos),
      (err) => this.onError(err),
      { enableHighAccuracy: true, maximumAge: 1000, timeout: 20000 }
    )
  }

  onPosition(position) {
    const { latitude, longitude, accuracy } = position.coords
    const user = [latitude, longitude]

    const distance = this.haversine(latitude, longitude, this.carLatValue, this.carLngValue)
    this.bearingToCar = this.bearing(latitude, longitude, this.carLatValue, this.carLngValue)

    this.renderDistance(distance)
    if (this.hasArrowTarget) this.arrowTarget.style.visibility = ""
    this.renderBearing()
    this.setStatus(`You're here · ±${Math.round(accuracy)} m`)
    this.updateUserOnMap(user, accuracy)
  }

  onError(err) {
    const map = {
      1: "Location permission denied — enable it to navigate back.",
      2: "Location unavailable right now.",
      3: "Still trying to pin down your location…"
    }
    this.setStatus(map[err.code] || "Couldn't get your location.")
  }

  updateUserOnMap(user, accuracy) {
    if (!this.map) return

    if (!this.userMarker) {
      const youIcon = L.divIcon({
        className: "",
        html: '<div style="width:16px;height:16px;border-radius:9999px;background:#6f9ebe;border:3px solid white;box-shadow:0 0 0 2px #6f9ebe"></div>',
        iconSize: [16, 16],
        iconAnchor: [8, 8]
      })
      this.userMarker = L.marker(user, { icon: youIcon }).addTo(this.map)
      this.userCircle = L.circle(user, { radius: accuracy, color: "#6f9ebe", weight: 1, fillOpacity: 0.08 }).addTo(this.map)
      this.line = L.polyline([user, this.car], { color: "#3a5f97", weight: 3, dashArray: "6 8" }).addTo(this.map)
    } else {
      this.userMarker.setLatLng(user)
      this.userCircle.setLatLng(user).setRadius(accuracy)
      this.line.setLatLngs([user, this.car])
    }

    this.map.fitBounds(L.latLngBounds([user, this.car]).pad(0.35), { maxZoom: 19 })
  }

  bindCompass() {
    this.boundOrientation = this.onOrientation.bind(this)
    // iOS 13+ requires an explicit permission request triggered by a tap;
    // that's handled by enableCompass(). Non-iOS browsers emit events directly.
    window.addEventListener("deviceorientationabsolute", this.boundOrientation, true)
    window.addEventListener("deviceorientation", this.boundOrientation, true)
  }

  // Called from a button tap (needed for iOS permission prompt).
  enableCompass() {
    const fn = window.DeviceOrientationEvent && DeviceOrientationEvent.requestPermission
    if (typeof fn === "function") {
      DeviceOrientationEvent.requestPermission()
        .then((state) => {
          if (state === "granted" && this.hasCompassNoteTarget) {
            this.compassNoteTarget.classList.add("hidden")
          }
        })
        .catch(() => {})
    }
  }

  onOrientation(event) {
    let heading = null
    if (typeof event.webkitCompassHeading === "number") {
      heading = event.webkitCompassHeading // iOS: degrees clockwise from north
    } else if (event.absolute && typeof event.alpha === "number") {
      heading = 360 - event.alpha
    }
    if (heading !== null && !Number.isNaN(heading)) {
      this.heading = heading
      this.renderBearing()
    }
  }

  renderBearing() {
    if (this.bearingToCar == null) return

    // Rotate the arrow so it points toward the car relative to where the phone
    // is facing. Without a compass, it points relative to true north.
    const relative = this.heading == null
      ? this.bearingToCar
      : (this.bearingToCar - this.heading + 360) % 360

    if (this.hasArrowTarget) {
      this.arrowTarget.style.transform = `rotate(${relative}deg)`
    }
    if (this.hasBearingTarget) {
      this.bearingTarget.textContent = this.compassLabel(this.bearingToCar)
    }
  }

  renderDistance(meters) {
    if (!this.hasDistanceTarget) return
    if (meters < 1000) {
      this.distanceTarget.textContent = Math.round(meters)
      if (this.hasDistanceUnitTarget) this.distanceUnitTarget.textContent = "m away"
    } else {
      this.distanceTarget.textContent = (meters / 1000).toFixed(2)
      if (this.hasDistanceUnitTarget) this.distanceUnitTarget.textContent = "km away"
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  // Haversine distance in meters.
  haversine(lat1, lon1, lat2, lon2) {
    const R = 6371000
    const toRad = (d) => (d * Math.PI) / 180
    const dLat = toRad(lat2 - lat1)
    const dLon = toRad(lon2 - lon1)
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2
    return 2 * R * Math.asin(Math.sqrt(a))
  }

  // Initial bearing from point 1 to point 2, degrees clockwise from north.
  bearing(lat1, lon1, lat2, lon2) {
    const toRad = (d) => (d * Math.PI) / 180
    const toDeg = (r) => (r * 180) / Math.PI
    const dLon = toRad(lon2 - lon1)
    const y = Math.sin(dLon) * Math.cos(toRad(lat2))
    const x =
      Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
      Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(dLon)
    return (toDeg(Math.atan2(y, x)) + 360) % 360
  }

  compassLabel(deg) {
    const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return dirs[Math.round(deg / 45) % 8]
  }
}
