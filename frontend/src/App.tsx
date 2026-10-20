import { useEffect, useRef, useState } from "react"
import { BrowserRouter, Link, Navigate, Route, Routes, useLocation, useNavigate, useParams } from "react-router-dom"
import { onAuthStateChanged, signInAnonymously, signOut, type User } from "firebase/auth"
import { AlertCircle, ArrowLeft, Camera, Check, Compass, Download, MapPin, Navigation, RefreshCw, ShieldCheck, Trash2, Upload } from "lucide-react"
import { setAnalyticsConsent, trackPageView } from "./analytics"
import { auth, firebaseConfigured } from "./firebase"
import { clearPrivacyChoices, DEFAULT_PRIVACY_CHOICES, readPrivacyChoices, savePrivacyChoices } from "./privacy"
import { createParkingSpot, deleteAllParkingData, deleteParkingSpot, exportParkingData, getActiveSpot, listActiveSpots, loadPrivatePhoto, purgeExpiredParkingData } from "./parkingService"
import MapView from "./MapView"
import VehicleIcon from "./VehicleIcon"
import { VEHICLE_TYPES, type ParkingSpot, type PrivacyChoices, type SpotDraft, type VehicleType } from "./types"

const emptyDraft: SpotDraft = {
  vehicleType: "car", latitude: null, longitude: null, accuracy: null,
  gpsUnavailable: false, mall: "", floor: "", section: "", slot: "", landmark: "", photo: null,
}

function AppRoutes({ user, choices, setChoices }: { user: User | null; choices: PrivacyChoices; setChoices: (next: PrivacyChoices) => void }) {
  const location = useLocation()
  useEffect(() => { void trackPageView(location.pathname, choices.analytics) }, [choices.analytics, location.pathname])

  return <div className="app-shell">
    <header className="topbar">
      <Link className="brand" to="/" aria-label="ParkBack home"><span className="brand-mark"><MapPin size={19} strokeWidth={2.2} /></span><span>Park<span className="brand-accent">Back</span></span></Link>
    </header>
    <main className="page-frame">
      {!firebaseConfigured ? <FirebaseSetup /> : !user ? <Loading label="Connecting securely…" /> : <Routes>
        <Route path="/" element={<Home user={user} />} />
        <Route path="/new" element={<SavePage user={user} choices={choices} />} />
        <Route path="/find/:id" element={<FindPage user={user} choices={choices} />} />
        <Route path="/privacy" element={<PrivacyPage user={user} choices={choices} setChoices={setChoices} />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>}
    </main>
  </div>
}

export default function App() {
  const [user, setUser] = useState<User | null>(null)
  const [choices, setChoices] = useState<PrivacyChoices>(() => readPrivacyChoices())
  const [authError, setAuthError] = useState("")

  useEffect(() => {
    const firebaseAuth = auth
    if (!firebaseAuth) return
    return onAuthStateChanged(firebaseAuth, (currentUser) => {
      if (currentUser) {
        setAuthError("")
        void purgeExpiredParkingData(currentUser.uid)
          .catch((error: Error) => console.warn("Expired ParkBack data cleanup failed", error))
          .finally(() => setUser(currentUser))
      }
      else void signInAnonymously(firebaseAuth).catch((error: Error) => setAuthError(error.message))
    }, (error) => setAuthError(error.message))
  }, [])
  useEffect(() => { void setAnalyticsConsent(choices.analytics) }, [choices.analytics])

  function updateChoices(next: PrivacyChoices) {
    savePrivacyChoices(next)
    setChoices(next)
  }

  return <BrowserRouter basename={import.meta.env.BASE_URL}>
    <AppRoutes user={user} choices={choices} setChoices={updateChoices} />
    {authError && <div className="toast toast-error" role="alert"><AlertCircle size={17} /> {authError}</div>}
  </BrowserRouter>
}

function FirebaseSetup() {
  return <section className="setup-panel">
    <div className="eyebrow"><ShieldCheck size={15} /> SECURE SETUP</div>
    <h1>Connect ParkBack to Firebase</h1>
    <p>The React app is ready. Add the Firebase web configuration to <code>frontend/.env.local</code>, then enable Anonymous Authentication, Firestore, and Realtime Database in your Firebase project.</p>
    <p className="setup-guide-note">Follow <code>docs/firebase-setup.md</code> in the repository to configure and deploy the Firebase project.</p>
  </section>
}

function Loading({ label }: { label: string }) { return <div className="loading-state"><span className="loader" />{label}</div> }

function Home({ user }: { user: User }) {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const navigate = useNavigate()
  useEffect(() => {
    let alive = true
    listActiveSpots(user.uid).then((spots) => {
      if (!alive) return
      if (spots[0]) navigate(`/find/${spots[0].id}`, { replace: true })
      setLoading(false)
    }).catch((problem: Error) => { if (alive) { setError(problem.message); setLoading(false) } })
    return () => { alive = false }
  }, [navigate, user.uid])
  if (loading) return <Loading label="Checking your saved spot…" />
  if (error) return <ErrorPanel message={error} action={<button className="button button-secondary" onClick={() => window.location.reload()}><RefreshCw size={16} /> Try again</button>} />
  return <SavePage user={user} choices={readPrivacyChoices()} />
}

function SavePage({ user, choices }: { user: User; choices: PrivacyChoices }) {
  const [draft, setDraft] = useState<SpotDraft>(emptyDraft)
  const [locationStatus, setLocationStatus] = useState("Location not requested")
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState("")
  const [photoPreview, setPhotoPreview] = useState("")
  const fileInput = useRef<HTMLInputElement>(null)
  const navigate = useNavigate()

  useEffect(() => {
    if (!draft.photo) { setPhotoPreview(""); return }
    const preview = URL.createObjectURL(draft.photo)
    setPhotoPreview(preview)
    return () => URL.revokeObjectURL(preview)
  }, [draft.photo])

  function setField<K extends keyof SpotDraft>(key: K, value: SpotDraft[K]) {
    setDraft((previous) => ({ ...previous, [key]: value }))
  }

  function requestLocation() {
    setError("")
    if (!navigator.geolocation) {
      setLocationStatus("Location services are unavailable. Add a photo to save without GPS.")
      setDraft((previous) => ({ ...previous, latitude: null, longitude: null, accuracy: null, gpsUnavailable: true }))
      return
    }
    setLocationStatus("Getting your location…")
    setDraft((previous) => ({ ...previous, latitude: null, longitude: null, accuracy: null, gpsUnavailable: false }))
    navigator.geolocation.getCurrentPosition(({ coords }) => {
      setDraft((previous) => ({ ...previous, latitude: coords.latitude, longitude: coords.longitude, accuracy: Math.round(coords.accuracy), gpsUnavailable: false }))
      setLocationStatus(`Location locked in · ±${Math.round(coords.accuracy)} m accuracy`)
    }, (problem) => {
      const messages: Record<number, string> = { 1: "Location permission denied. Add a photo or enable GPS.", 2: "Location unavailable. Add a photo or try again.", 3: "GPS timed out. Add a photo or try again." }
      setLocationStatus(messages[problem.code] ?? "Could not get your location. Add a photo or try again.")
      setDraft((previous) => ({ ...previous, latitude: null, longitude: null, accuracy: null, gpsUnavailable: true }))
    }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 })
  }

  const hasDetails = [draft.mall, draft.floor, draft.section, draft.slot, draft.landmark].some((value) => value.trim())
  const locationReady = draft.latitude !== null && draft.longitude !== null
  const canSave = draft.gpsUnavailable ? !!draft.photo : locationReady && (hasDetails || !!draft.photo)

  async function saveSpot(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setSubmitting(true)
    setError("")
    try {
      const spot = await createParkingSpot(user.uid, draft)
      navigate(`/find/${spot.id}`)
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "Could not save this spot. Try again.")
    } finally { setSubmitting(false) }
  }

  function choosePhoto(capture: boolean) {
    if (!fileInput.current) return
    if (capture) fileInput.current.setAttribute("capture", "environment")
    else fileInput.current.removeAttribute("capture")
    fileInput.current.click()
  }

  return <section className="screen screen-save">
    <div className="screen-heading"><h1>Where did you park?</h1><p>Save your parking spot and find your way back.</p></div>
    {error && <div className="inline-alert" role="alert"><AlertCircle size={17} />{error}</div>}
    <form onSubmit={saveSpot} className="save-form">
      <fieldset className="field-group vehicle-group"><legend>What are you parking?</legend><div className="vehicle-options">
        {VEHICLE_TYPES.map((vehicle) => <label key={vehicle} className={`vehicle-option${draft.vehicleType === vehicle ? " selected" : ""}`}>
          <input type="radio" name="vehicle" value={vehicle} checked={draft.vehicleType === vehicle} onChange={() => setField("vehicleType", vehicle as VehicleType)} /><VehicleIcon type={vehicle} size={22} /><span>{vehicle}</span>
        </label>)}
      </div></fieldset>

      <section className="location-panel">
        <div className="location-topline">
          <span className={`location-indicator${locationReady ? " ready" : draft.gpsUnavailable ? " unavailable" : ""}`}><MapPin size={18} /></span>
          <div className="location-copy"><strong>{locationStatus}</strong><small>{locationReady ? "Only the parked pin is saved." : draft.gpsUnavailable ? "A photo will be required instead of a pin." : "Tap when you're beside your vehicle."}</small></div>
          <button type="button" onClick={requestLocation} className="button button-location"><Navigation size={15} /> Use location</button>
        </div>
        {choices.maps ? <MapView parked={locationReady ? [draft.latitude!, draft.longitude!] : null} compact /> : <p className="map-off-note">Maps are off by your choice. GPS still works. <Link to="/privacy">Privacy choices</Link></p>}
        <p className="map-disclosure">{choices.maps ? "OpenStreetMap receives your IP address and map area." : "No map tiles are loaded."} GPS is requested only when you tap Use location.</p>
      </section>

      <div className="details-group">
        <div className="details-heading"><span>Add details</span><span className="legend-hint">{draft.gpsUnavailable ? "(photo required)" : "(optional)"}</span></div>
        <fieldset className="details-panel">
        <div className="details-grid">
          <label className="form-field field-wide"><span>Mall or building</span><input maxLength={120} value={draft.mall} onChange={(event) => setField("mall", event.target.value)} placeholder="SM Megamall" /></label>
          <label className="form-field"><span>Floor</span><input maxLength={120} value={draft.floor} onChange={(event) => setField("floor", event.target.value)} placeholder="B2" /></label>
          <label className="form-field"><span>Section or zone</span><input maxLength={120} value={draft.section} onChange={(event) => setField("section", event.target.value)} placeholder="Blue" /></label>
          <label className="form-field field-wide"><span>Slot number</span><input maxLength={120} value={draft.slot} onChange={(event) => setField("slot", event.target.value)} placeholder="B2-147" /></label>
          <label className="form-field field-wide"><span>Nearby landmark</span><textarea maxLength={500} rows={2} value={draft.landmark} onChange={(event) => setField("landmark", event.target.value)} placeholder="Near the elevator by the food court" /></label>
        </div>
        <div className="photo-block">
          <input ref={fileInput} type="file" accept="image/png,image/jpeg,image/webp,image/heic" className="visually-hidden" onChange={(event) => setField("photo", event.target.files?.[0] ?? null)} />
          {photoPreview ? <div className="photo-preview-wrap"><img className="photo-preview" src={photoPreview} alt="Parking area preview" /><button type="button" className="icon-button photo-remove" onClick={() => { setField("photo", null); if (fileInput.current) fileInput.current.value = "" }} aria-label="Remove photo"><Trash2 size={17} /></button></div> :
            <div className="photo-actions"><button type="button" className="button button-secondary" onClick={() => choosePhoto(true)}><Camera size={17} /> Take photo</button><button type="button" className="button button-secondary" onClick={() => choosePhoto(false)}><Upload size={17} /> Choose photo</button></div>}
          <small>{draft.gpsUnavailable ? "Photo required without GPS · up to 5 MB" : "Photo optional · PNG, JPEG, WEBP, or HEIC · up to 5 MB"}</small>
        </div>
        </fieldset>
      </div>
      {!canSave && (locationReady || draft.gpsUnavailable) && <p className="form-hint">{draft.gpsUnavailable ? "Add a photo to save without GPS." : "Add at least one detail or photo to save this spot."}</p>}
      <p className="retention-note">Your spot and photo are deleted when you confirm you found your vehicle. Unfound spots expire after seven days. <Link to="/privacy">Privacy details</Link></p>
      <button type="submit" className="button button-primary save-button" disabled={!canSave || submitting}>{submitting ? <><span className="button-spinner" /> Saving securely…</> : <><MapPin size={18} /> Save parking spot</>}</button>
    </form>
  </section>
}

function FindPage({ user, choices }: { user: User; choices: PrivacyChoices }) {
  const { id = "" } = useParams()
  const [spot, setSpot] = useState<ParkingSpot | null>(null)
  const [photoUrl, setPhotoUrl] = useState("")
  const [photoUnavailable, setPhotoUnavailable] = useState(false)
  const [current, setCurrent] = useState<[number, number] | null>(null)
  const [accuracy, setAccuracy] = useState<number | null>(null)
  const [heading, setHeading] = useState<number | null>(null)
  const [status, setStatus] = useState("Locating you…")
  const [elapsed, setElapsed] = useState("")
  const [error, setError] = useState("")
  const [deleting, setDeleting] = useState(false)
  const navigate = useNavigate()

  useEffect(() => {
    let alive = true
    getActiveSpot(user.uid, id).then((result) => {
      if (!alive) return
      if (!result) { navigate("/", { replace: true }); return }
      setSpot(result)
      if (result.photoKey) loadPrivatePhoto(user.uid, result.photoKey).then((dataUrl) => {
        if (alive) setPhotoUrl(dataUrl)
      }).catch(() => { if (alive) setPhotoUnavailable(true) })
    }).catch((problem: Error) => { if (alive) setError(problem.message) })
    return () => { alive = false }
  }, [id, navigate, user.uid])

  useEffect(() => {
    if (!spot) return
    const updateClock = () => {
      const seconds = Math.max(0, Math.floor((Date.now() - spot.savedAt.getTime()) / 1000))
      const hours = Math.floor(seconds / 3600)
      const minutes = Math.floor((seconds % 3600) / 60)
      setElapsed(hours ? `${hours}h ${minutes}m` : minutes ? `${minutes}m` : `${seconds}s`)
      if (Date.now() >= spot.expiresAt.getTime()) navigate("/", { replace: true })
    }
    updateClock()
    const timer = window.setInterval(updateClock, 1000)
    return () => window.clearInterval(timer)
  }, [navigate, spot])

  useEffect(() => {
    if (!spot || spot.gpsUnavailable || !navigator.geolocation) return
    const watch = navigator.geolocation.watchPosition(({ coords }) => {
      setCurrent([coords.latitude, coords.longitude])
      setAccuracy(coords.accuracy)
      setStatus(`You're here · ±${Math.round(coords.accuracy)} m`)
    }, (problem) => {
      const messages: Record<number, string> = { 1: "Location permission denied. Enable it to navigate back.", 2: "Location unavailable right now.", 3: "Still trying to find your location…" }
      setStatus(messages[problem.code] ?? "Could not get your location.")
    }, { enableHighAccuracy: true, maximumAge: 1000, timeout: 20000 })
    return () => navigator.geolocation.clearWatch(watch)
  }, [spot])

  useEffect(() => {
    if (!spot || spot.gpsUnavailable) return
    const onOrientation = (event: DeviceOrientationEvent & { webkitCompassHeading?: number }) => {
      if (typeof event.webkitCompassHeading === "number") setHeading(event.webkitCompassHeading)
      else if (event.absolute && typeof event.alpha === "number") setHeading(360 - event.alpha)
    }
    window.addEventListener("deviceorientationabsolute", onOrientation as EventListener, true)
    window.addEventListener("deviceorientation", onOrientation as EventListener, true)
    return () => {
      window.removeEventListener("deviceorientationabsolute", onOrientation as EventListener, true)
      window.removeEventListener("deviceorientation", onOrientation as EventListener, true)
    }
  }, [spot])

  const parked = spot && !spot.gpsUnavailable && spot.latitude !== null && spot.longitude !== null ? [spot.latitude, spot.longitude] as [number, number] : null
  const distance = parked && current ? haversine(current[0], current[1], parked[0], parked[1]) : null
  const bearing = parked && current ? calculateBearing(current[0], current[1], parked[0], parked[1]) : null
  const relativeBearing = bearing === null ? null : (bearing - (heading ?? 0) + 360) % 360
  const details = spot ? [["Mall / building", spot.mall], ["Floor", spot.floor], ["Section / zone", spot.section], ["Slot number", spot.slot], ["Landmark", spot.landmark]].filter(([, value]) => value) : []

  async function enableCompass() {
    const orientation = window.DeviceOrientationEvent as typeof DeviceOrientationEvent & { requestPermission?: () => Promise<string> }
    if (typeof orientation.requestPermission === "function") {
      try { await orientation.requestPermission() } catch { /* North-referenced guidance remains available. */ }
    }
  }

  function refreshPosition() {
    if (!navigator.geolocation) return
    setStatus("Locating you…")
    navigator.geolocation.getCurrentPosition(({ coords }) => {
      setCurrent([coords.latitude, coords.longitude])
      setAccuracy(coords.accuracy)
      setStatus(`You're here · ±${Math.round(coords.accuracy)} m`)
    }, () => setStatus("Location unavailable right now. Keep trying or check browser permissions."), { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 })
  }

  async function foundVehicle() {
    if (!spot) return
    setDeleting(true)
    setError("")
    try { await deleteParkingSpot(user.uid, spot); navigate("/", { replace: true }) }
    catch (problem) { setError(problem instanceof Error ? problem.message : "Could not delete this spot."); setDeleting(false) }
  }

  if (error && !spot) return <ErrorPanel message={error} action={<Link className="button button-secondary" to="/"><ArrowLeft size={16} /> Back to save</Link>} />
  if (!spot) return <Loading label="Opening your saved spot…" />

  return <section className="screen screen-find">
    <Link to="/new" className="back-link"><ArrowLeft size={16} /> Save a different spot</Link>
    <div className="find-heading"><div className="vehicle-stamp"><VehicleIcon type={spot.vehicleType} size={20} /></div><div><div className="eyebrow">YOUR PARKING SPOT</div><h1>Find your {spot.vehicleType}</h1><span className="vehicle-type-pill">{spot.vehicleType}</span><p className="find-status">{spot.gpsUnavailable ? "Saved without GPS. Use your photo and notes below." : status}</p></div></div>
    <div className="time-strip"><span>Parked <strong>{elapsed}</strong> ago</span><span>Expires {spot.expiresAt.toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}</span></div>
    {parked && <div className="navigation-grid">
      <div className="compass-panel"><span className="north-label">N</span><Navigation size={42} className="compass-arrow" style={{ transform: `rotate(${relativeBearing ?? bearing ?? 0}deg)` }} /><span className="compass-caption">{bearing === null ? "Waiting for your location" : `${compassLabel(bearing)} to your car`}</span></div>
      <div className="distance-panel"><strong>{distance === null ? "--" : distance < 1000 ? `${Math.round(distance)}` : `${(distance / 1000).toFixed(2)}`}</strong><span>{distance === null ? "waiting" : distance < 1000 ? "meters away" : "kilometers away"}</span><small>{accuracy === null ? "GPS warming up" : `Your location ±${Math.round(accuracy)} m`}</small></div>
    </div>}
    {parked && <div className="map-section">
      {choices.maps ? <MapView parked={parked} current={current} accuracy={accuracy} /> : <div className="map-off-panel"><MapPin size={19} /><span>Maps are off. <Link to="/privacy">Change privacy choices</Link></span></div>}
      <div className="map-actions"><button className="compass-permission" type="button" onClick={refreshPosition}><RefreshCw size={15} /> Refresh my location</button>{bearing !== null && heading === null && <button className="compass-permission" type="button" onClick={() => void enableCompass()}><Compass size={15} /> Enable compass</button>}</div>
    </div>}
    {photoUrl && <img className="saved-photo" src={photoUrl} alt="Saved parking area" />}
    {spot.photoKey && photoUnavailable && <p className="photo-warning" role="status">Photo file is unavailable. Your saved location and notes are still here.</p>}
    {details.length > 0 && <dl className="detail-list">{details.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>}
    {error && <div className="inline-alert" role="alert"><AlertCircle size={17} />{error}</div>}
    <button type="button" className="button button-found" onClick={() => void foundVehicle()} disabled={deleting}>{deleting ? <><span className="button-spinner" /> Clearing spot…</> : <><Check size={19} /> I found my {spot.vehicleType}</>}</button>
    <p className="delete-hint">This removes the saved pin, details, and photo from your account.</p>
  </section>
}

function PrivacyPage({ user, choices, setChoices }: { user: User; choices: PrivacyChoices; setChoices: (next: PrivacyChoices) => void }) {
  const [draft, setDraft] = useState(choices)
  const [message, setMessage] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const navigate = useNavigate()
  useEffect(() => setDraft(choices), [choices])

  async function saveChoices(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setChoices(draft)
    await setAnalyticsConsent(draft.analytics)
    setMessage("Your privacy choices are saved on this device.")
  }

  async function downloadData() {
    setError("")
    try {
      const json = await exportParkingData(user.uid)
      const url = URL.createObjectURL(new Blob([json], { type: "application/json" }))
      const link = document.createElement("a")
      link.href = url
      link.download = "parkback-data.json"
      link.click()
      URL.revokeObjectURL(url)
    } catch (problem) { setError(problem instanceof Error ? problem.message : "Could not export your data.") }
  }

  async function deleteData() {
    if (!window.confirm("Delete all active parking spots and photos saved in this browser? This cannot be undone.")) return
    setBusy(true)
    setError("")
    try {
      await deleteAllParkingData(user.uid)
      clearPrivacyChoices()
      setChoices(DEFAULT_PRIVACY_CHOICES)
      await setAnalyticsConsent(false)
      if (auth) await signOut(auth)
      navigate("/", { replace: true })
      setMessage("Your active parking records and photos have been deleted. Optional analytics is off.")
    } catch (problem) { setError(problem instanceof Error ? problem.message : "Could not delete all your data.") }
    finally { setBusy(false) }
  }

  return <section className="screen screen-privacy">
    <div className="screen-heading privacy-heading"><div className="eyebrow"><ShieldCheck size={15} /> YOUR DATA, YOUR CALL</div><h1>Privacy</h1><p>Location access stays in your control. We save only the parked spot you choose to share.</p></div>
    {message && <div className="inline-success" role="status"><Check size={16} />{message}</div>}
    {error && <div className="inline-alert" role="alert"><AlertCircle size={17} />{error}</div>}
    <form className="privacy-section choices-form" onSubmit={(event) => void saveChoices(event)}>
      <h2>Your choices</h2>
      <label className="choice-row"><input type="checkbox" checked={draft.maps} onChange={(event) => setDraft((current) => ({ ...current, maps: event.target.checked }))} /><span><strong>Maps</strong><small>On by default. OpenStreetMap receives your IP address and the map area. Turn maps off to stop loading map tiles; GPS still works.</small></span></label>
      <label className="choice-row"><input type="checkbox" checked={draft.analytics} onChange={(event) => setDraft((current) => ({ ...current, analytics: event.target.checked }))} /><span><strong>Optional analytics</strong><small>Off unless you opt in. Firebase Analytics may receive page views, device information, IP address, and browser identifiers. Parking details and location coordinates are never sent as analytics events.</small></span></label>
      <p className="section-note">GPS starts only when you tap Use location. On the find screen, your browser location and compass are used for navigation and are not saved.</p>
      <button type="submit" className="button button-primary"><Check size={17} /> Save choices</button>
    </form>
    <section className="privacy-section data-actions"><h2>Your parking data</h2><p>Download an export of active parking records, or permanently remove active spots and their photos.</p><div className="action-row">
      <button type="button" className="button button-secondary" onClick={() => void downloadData()}><Download size={17} /> Download data</button>
      <button type="button" className="button button-danger" onClick={() => void deleteData()} disabled={busy}>{busy ? <><span className="button-spinner" /> Deleting…</> : <><Trash2 size={16} /> Delete my data</>}</button>
    </div></section>
    <section className="privacy-section"><h2>What ParkBack stores</h2><p>When you save a spot, ParkBack stores its GPS coordinates and accuracy if available, vehicle type, time, details, and any photo you choose. If GPS is unavailable, a photo is required instead of a pin. A Firebase anonymous identifier keeps your records private to this browser; no account form is required.</p><p>Photos are stored as Base64 data in a private Realtime Database path and fetched only with your Firebase identity. Your walking location and compass readings stay in your browser. Photos may contain embedded location or camera details.</p></section>
    <section className="privacy-section"><h2>Retention and deletion</h2><p>Parking spots expire after seven days. Confirming you found your vehicle deletes that spot and its photo. Delete my data removes all spots linked to this browser. Expired records and photos are removed the next time this browser opens ParkBack; if you never return, they can remain stored beyond seven days.</p><p>Clearing this browser’s site data can make its anonymous identity and saved records inaccessible. Privacy choices are stored locally on this device.</p></section>
    <section className="privacy-section contact-section"><h2>Questions or requests?</h2><p>ParkBack is run by Lovely Joy Figueras. Email <a href="mailto:lovelyfigueras@gmail.com">lovelyfigueras@gmail.com</a> for access, correction, or deletion requests. You may also contact the <a href="https://privacy.gov.ph/" target="_blank" rel="noreferrer">National Privacy Commission</a>.</p></section>
    <Link to="/" className="back-link privacy-back-link"><ArrowLeft size={16} /> Back to ParkBack</Link>
  </section>
}

function ErrorPanel({ message, action }: { message: string; action?: React.ReactNode }) {
  return <section className="error-panel"><span className="error-icon"><AlertCircle size={20} /></span><h1>We couldn’t load ParkBack.</h1><p>{message}</p>{action}</section>
}

function haversine(lat1: number, lon1: number, lat2: number, lon2: number) {
  const radians = (degrees: number) => degrees * Math.PI / 180
  const latitudeDelta = radians(lat2 - lat1)
  const longitudeDelta = radians(lon2 - lon1)
  const value = Math.sin(latitudeDelta / 2) ** 2 + Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(longitudeDelta / 2) ** 2
  return 6371000 * 2 * Math.asin(Math.sqrt(value))
}

function calculateBearing(lat1: number, lon1: number, lat2: number, lon2: number) {
  const radians = (degrees: number) => degrees * Math.PI / 180
  const degrees = (radiansValue: number) => radiansValue * 180 / Math.PI
  const longitudeDelta = radians(lon2 - lon1)
  const y = Math.sin(longitudeDelta) * Math.cos(radians(lat2))
  const x = Math.cos(radians(lat1)) * Math.sin(radians(lat2)) - Math.sin(radians(lat1)) * Math.cos(radians(lat2)) * Math.cos(longitudeDelta)
  return (degrees(Math.atan2(y, x)) + 360) % 360
}

function compassLabel(degrees: number) { return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(degrees / 45) % 8] }
