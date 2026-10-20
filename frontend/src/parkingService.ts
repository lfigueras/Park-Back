import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  setDoc,
  where,
} from "firebase/firestore"
import { get, ref as databaseRef, remove, set } from "firebase/database"
import { db, realtimeDb } from "./firebase"
import type { ParkingSpot, SpotDraft, VehicleType } from "./types"

const RETENTION_DAYS = 7
const MAX_PHOTO_BYTES = 5 * 1024 * 1024
const ALLOWED_PHOTO_TYPES = new Set(["image/png", "image/jpeg", "image/jpg", "image/webp", "image/heic"])
const DETAIL_FIELDS = ["mall", "floor", "section", "slot", "landmark"] as const

type StoredSpot = {
  vehicleType: VehicleType
  latitude: number | null
  longitude: number | null
  accuracy: number | null
  gpsUnavailable: boolean
  mall: string
  floor: string
  section: string
  slot: string
  landmark: string
  savedAt: Timestamp
  expiresAt: Timestamp
  photoKey: string | null
}

function locationsFor(uid: string) {
  if (!db) throw new Error("Firebase is not configured.")
  return collection(db, "users", uid, "parkingLocations")
}

function asParkingSpot(id: string, data: StoredSpot): ParkingSpot {
  return {
    id,
    vehicleType: data.vehicleType,
    latitude: data.latitude,
    longitude: data.longitude,
    accuracy: data.accuracy,
    gpsUnavailable: data.gpsUnavailable,
    mall: data.mall,
    floor: data.floor,
    section: data.section,
    slot: data.slot,
    landmark: data.landmark,
    savedAt: data.savedAt.toDate(),
    expiresAt: data.expiresAt.toDate(),
    photoKey: data.photoKey,
  }
}

function privatePhotoRef(uid: string, photoKey: string) {
  if (!realtimeDb) throw new Error("Realtime Database is not configured.")
  return databaseRef(realtimeDb, `users/${uid}/parkingPhotos/${photoKey}`)
}

function fileAsBase64(photo: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.addEventListener("load", () => {
      const result = reader.result
      if (typeof result !== "string") {
        reject(new Error("Could not read this photo."))
        return
      }
      resolve(result.slice(result.indexOf(",") + 1))
    }, { once: true })
    reader.addEventListener("error", () => reject(new Error("Could not read this photo.")), { once: true })
    reader.readAsDataURL(photo)
  })
}

async function storePrivatePhoto(uid: string, photoKey: string, photo: File) {
  const base64 = await fileAsBase64(photo)
  await set(privatePhotoRef(uid, photoKey), { contentType: photo.type, base64 })
}

async function removePrivatePhoto(uid: string, photoKey: string) {
  await remove(privatePhotoRef(uid, photoKey))
}

function validateDraft(draft: SpotDraft) {
  if (draft.gpsUnavailable && !draft.photo) {
    throw new Error("Add a photo to save a spot without GPS.")
  }
  if (!draft.gpsUnavailable && (draft.latitude === null || draft.longitude === null)) {
    throw new Error("Use your location before saving this spot.")
  }
  if (!DETAIL_FIELDS.some((field) => draft[field].trim()) && !draft.photo) {
    throw new Error("Add a floor, section, slot, landmark, or photo before saving.")
  }
  if (draft.photo) {
    if (draft.photo.size > MAX_PHOTO_BYTES) throw new Error("Choose a photo smaller than 5 MB.")
    if (!ALLOWED_PHOTO_TYPES.has(draft.photo.type)) {
      throw new Error("Use a PNG, JPEG, WEBP, or HEIC photo.")
    }
  }
  if (!draft.gpsUnavailable) {
    if (draft.latitude! < -90 || draft.latitude! > 90 || draft.longitude! < -180 || draft.longitude! > 180) {
      throw new Error("The location coordinates are invalid. Try requesting GPS again.")
    }
  }
}

export async function createParkingSpot(uid: string, draft: SpotDraft): Promise<ParkingSpot> {
  if (!db || !realtimeDb) throw new Error("Firebase is not configured.")
  validateDraft(draft)

  const spotRef = doc(locationsFor(uid))
  const now = Timestamp.now()
  const expiresAt = Timestamp.fromMillis(now.toMillis() + RETENTION_DAYS * 24 * 60 * 60 * 1000)
  const photoKey = draft.photo ? spotRef.id : null

  if (draft.photo && photoKey) await storePrivatePhoto(uid, photoKey, draft.photo)

  const data: StoredSpot = {
    vehicleType: draft.vehicleType,
    latitude: draft.gpsUnavailable ? null : draft.latitude,
    longitude: draft.gpsUnavailable ? null : draft.longitude,
    accuracy: draft.gpsUnavailable ? null : draft.accuracy,
    gpsUnavailable: draft.gpsUnavailable,
    mall: draft.mall.trim(),
    floor: draft.floor.trim(),
    section: draft.section.trim(),
    slot: draft.slot.trim(),
    landmark: draft.landmark.trim(),
    savedAt: now,
    expiresAt,
    photoKey,
  }

  try {
    await setDoc(spotRef, data)
  } catch (error) {
    if (photoKey) await removePrivatePhoto(uid, photoKey).catch(() => undefined)
    throw error
  }

  return asParkingSpot(spotRef.id, data)
}

export async function listActiveSpots(uid: string): Promise<ParkingSpot[]> {
  const activeAfter = Timestamp.now()
  const activeQuery = query(
    locationsFor(uid),
    where("expiresAt", ">", activeAfter),
    orderBy("expiresAt", "asc"),
  )
  const snapshot = await getDocs(activeQuery)
  return snapshot.docs
    .map((item) => asParkingSpot(item.id, item.data() as StoredSpot))
    .sort((left, right) => right.savedAt.getTime() - left.savedAt.getTime())
}

export async function getActiveSpot(uid: string, id: string): Promise<ParkingSpot | null> {
  const snapshot = await getDoc(doc(locationsFor(uid), id))
  if (!snapshot.exists()) return null
  const spot = asParkingSpot(snapshot.id, snapshot.data() as StoredSpot)
  return spot.expiresAt.getTime() > Date.now() ? spot : null
}

export async function loadPrivatePhoto(uid: string, photoKey: string): Promise<string> {
  const snapshot = await get(privatePhotoRef(uid, photoKey))
  if (!snapshot.exists()) throw new Error("Photo file is unavailable.")
  const photo = snapshot.val() as { contentType?: unknown; base64?: unknown }
  if (typeof photo.contentType !== "string" || typeof photo.base64 !== "string") {
    throw new Error("Photo data is invalid.")
  }
  return `data:${photo.contentType};base64,${photo.base64}`
}

export async function deleteParkingSpot(uid: string, spot: ParkingSpot) {
  if (!db || !realtimeDb) throw new Error("Firebase is not configured.")
  if (spot.photoKey) await removePrivatePhoto(uid, spot.photoKey)
  await deleteDoc(doc(locationsFor(uid), spot.id))
}

export async function deleteAllParkingData(uid: string) {
  if (!db || !realtimeDb) throw new Error("Firebase is not configured.")
  const records = await getDocs(locationsFor(uid))
  await remove(databaseRef(realtimeDb, `users/${uid}/parkingPhotos`))
  await Promise.all(records.docs.map((record) => deleteDoc(record.ref)))
}

export async function purgeExpiredParkingData(uid: string) {
  if (!db || !realtimeDb) throw new Error("Firebase is not configured.")
  const expiredQuery = query(
    locationsFor(uid),
    where("expiresAt", "<=", Timestamp.now()),
    orderBy("expiresAt", "asc"),
  )
  const expiredRecords = await getDocs(expiredQuery)
  await Promise.all(expiredRecords.docs.map(async (record) => {
    const spot = record.data() as StoredSpot
    if (spot.photoKey) await removePrivatePhoto(uid, spot.photoKey)
    await deleteDoc(record.ref)
  }))
}

export async function exportParkingData(uid: string): Promise<string> {
  const spots = await listActiveSpots(uid)
  const parkingLocations = await Promise.all(spots.map(async ({ photoKey, ...spot }) => {
    let photoDataUrl: string | null = null
    if (photoKey) {
      const snapshot = await get(privatePhotoRef(uid, photoKey))
      if (snapshot.exists()) {
        const photo = snapshot.val() as { contentType?: unknown; base64?: unknown }
        if (typeof photo.contentType === "string" && typeof photo.base64 === "string") {
          photoDataUrl = `data:${photo.contentType};base64,${photo.base64}`
        }
      }
    }
    return {
      ...spot,
      savedAt: spot.savedAt.toISOString(),
      expiresAt: spot.expiresAt.toISOString(),
      photo_data_url: photoDataUrl,
    }
  }))

  return JSON.stringify({
    generated_at: new Date().toISOString(),
    parking_locations: parkingLocations,
  }, null, 2)
}
