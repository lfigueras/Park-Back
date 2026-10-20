import { initializeApp } from "firebase/app"
import { connectAuthEmulator, getAuth } from "firebase/auth"
import { connectFirestoreEmulator, getFirestore } from "firebase/firestore"
import { connectDatabaseEmulator, getDatabase } from "firebase/database"

const config = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  databaseURL: import.meta.env.VITE_FIREBASE_DATABASE_URL,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID,
}

export const firebaseConfigured = Boolean(
  config.apiKey && config.authDomain && config.projectId && config.databaseURL && config.appId,
)

export const firebaseApp = firebaseConfigured ? initializeApp(config) : null
export const auth = firebaseApp ? getAuth(firebaseApp) : null
export const db = firebaseApp ? getFirestore(firebaseApp) : null
export const realtimeDb = firebaseApp ? getDatabase(firebaseApp, config.databaseURL) : null
export const measurementId = config.measurementId

if (import.meta.env.VITE_USE_FIREBASE_EMULATORS === "true" && auth && db && realtimeDb) {
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true })
  connectFirestoreEmulator(db, "127.0.0.1", 8080)
  connectDatabaseEmulator(realtimeDb, "127.0.0.1", 9000)
}
