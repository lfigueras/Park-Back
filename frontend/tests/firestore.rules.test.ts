import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest"
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing"
import { Timestamp } from "firebase/firestore"

const projectId = "demo-parkback"
let testEnv: RulesTestEnvironment
const firestoreSettings = { experimentalForceLongPolling: true }

function validRecord(id: string, overrides: Record<string, unknown> = {}) {
  const savedAt = Timestamp.now()
  return {
    vehicleType: "car",
    latitude: 14.585,
    longitude: 121.056,
    accuracy: 12,
    gpsUnavailable: false,
    mall: "",
    floor: "",
    section: "",
    slot: "B2-147",
    landmark: "",
    savedAt,
    expiresAt: Timestamp.fromMillis(savedAt.toMillis() + 7 * 24 * 60 * 60 * 1000),
    photoKey: null,
    ...overrides,
  }
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
    },
    database: {
      host: "127.0.0.1",
      port: 9000,
    },
  })
}, 30_000)

afterAll(async () => {
  if (testEnv) await testEnv.cleanup()
})

describe("Firestore owner and retention rules", () => {
  it("allows a user to create and read their own active spot only", async () => {
    const owner = testEnv.authenticatedContext("owner").firestore(firestoreSettings)
    const other = testEnv.authenticatedContext("other").firestore(firestoreSettings)
    const ownerSpot = owner.doc("users/owner/parkingLocations/spot-1")

    await assertSucceeds(ownerSpot.set(validRecord("spot-1")))
    await assertSucceeds(ownerSpot.get())
    await assertFails(other.doc("users/owner/parkingLocations/spot-1").get())
    await assertFails(other.doc("users/owner/parkingLocations/spot-2").set(validRecord("spot-2")))
  })

  it("rejects missing GPS fallback photos, invalid coordinates, and mutable records", async () => {
    const owner = testEnv.authenticatedContext("owner").firestore(firestoreSettings)
    const collectionRef = owner.collection("users/owner/parkingLocations")
    const noPhoto = validRecord("no-photo", {
      latitude: null,
      longitude: null,
      accuracy: null,
      gpsUnavailable: true,
    })
    const invalidCoordinates = validRecord("bad-coordinates", { latitude: 91 })

    await assertFails(collectionRef.doc("no-photo").set(noPhoto))
    await assertFails(collectionRef.doc("bad-coordinates").set(invalidCoordinates))
    await assertSucceeds(collectionRef.doc("valid").set(validRecord("valid")))
    await assertFails(collectionRef.doc("valid").set(validRecord("valid")))
  })

  it("does not expose expired spots through reads or active-list queries", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const savedAt = Timestamp.fromMillis(Date.now() - 8 * 24 * 60 * 60 * 1000)
      await context.firestore(firestoreSettings).doc("users/owner/parkingLocations/expired").set(validRecord("expired", {
        savedAt,
        expiresAt: Timestamp.fromMillis(savedAt.toMillis() + 7 * 24 * 60 * 60 * 1000),
      }))
    })
    const owner = testEnv.authenticatedContext("owner").firestore(firestoreSettings)
    await assertFails(owner.doc("users/owner/parkingLocations/expired").get())
    await assertSucceeds(owner.collection("users/owner/parkingLocations").where("expiresAt", ">", Timestamp.now()).get().then((result) => {
      expect(result.empty).toBe(true)
    }))
  })
})

describe("Realtime Database photo privacy rules", () => {
  it("limits photo reads and writes to the owning anonymous user", async () => {
    const owner = testEnv.authenticatedContext("owner").database()
    const other = testEnv.authenticatedContext("other").database()
    const ownerRef = owner.ref("users/owner/parkingPhotos/spot-1")
    const otherRef = other.ref("users/owner/parkingPhotos/spot-1")
    const photo = { contentType: "image/jpeg", base64: "aGVsbG8=" }

    await assertSucceeds(ownerRef.set(photo))
    await assertSucceeds(ownerRef.once("value"))
    await assertFails(otherRef.once("value"))
    await assertFails(other.ref("users/other/parkingPhotos/spot-2").set(photo))
    await assertFails(ownerRef.set({ contentType: "text/plain", base64: "aGVsbG8=" }))
  })
})
