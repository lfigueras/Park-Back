import type { PrivacyChoices } from "./types"

const STORAGE_KEY = "parkback-privacy-v1"

export const DEFAULT_PRIVACY_CHOICES: PrivacyChoices = {
  maps: true,
  analytics: false,
}

export function readPrivacyChoices(): PrivacyChoices {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (!saved) return DEFAULT_PRIVACY_CHOICES
    const parsed = JSON.parse(saved) as Partial<PrivacyChoices>
    return {
      maps: typeof parsed.maps === "boolean" ? parsed.maps : DEFAULT_PRIVACY_CHOICES.maps,
      analytics: typeof parsed.analytics === "boolean" ? parsed.analytics : DEFAULT_PRIVACY_CHOICES.analytics,
    }
  } catch {
    return DEFAULT_PRIVACY_CHOICES
  }
}

export function savePrivacyChoices(choices: PrivacyChoices) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(choices))
}

export function clearPrivacyChoices() {
  localStorage.removeItem(STORAGE_KEY)
}
