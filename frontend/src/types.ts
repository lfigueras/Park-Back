export const VEHICLE_TYPES = ["car", "motorcycle", "bicycle", "truck"] as const

export type VehicleType = (typeof VEHICLE_TYPES)[number]

export type SpotDraft = {
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
  photo: File | null
}

export type ParkingSpot = Omit<SpotDraft, "photo"> & {
  id: string
  savedAt: Date
  expiresAt: Date
  photoKey: string | null
}

export type PrivacyChoices = {
  maps: boolean
  analytics: boolean
}
