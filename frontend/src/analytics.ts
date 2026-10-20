import { initializeAnalytics, isSupported, logEvent, setAnalyticsCollectionEnabled, type Analytics } from "firebase/analytics"
import { firebaseApp, measurementId } from "./firebase"

let analytics: Analytics | null = null

export async function setAnalyticsConsent(enabled: boolean) {
  if (!firebaseApp || !measurementId) return

  if (!enabled) {
    if (analytics) setAnalyticsCollectionEnabled(analytics, false)
    return
  }

  if (!(await isSupported())) return
  analytics ??= initializeAnalytics(firebaseApp, { config: { send_page_view: false } })
  setAnalyticsCollectionEnabled(analytics, true)
}

export async function trackPageView(path: string, enabled: boolean) {
  if (!enabled || !firebaseApp || !measurementId || !(await isSupported())) return
  analytics ??= initializeAnalytics(firebaseApp, { config: { send_page_view: false } })
  const safePath = path.startsWith("/find/") ? "/find/:id" : path
  logEvent(analytics, "page_view", { page_location: `${window.location.origin}${safePath}`, page_path: safePath })
}
