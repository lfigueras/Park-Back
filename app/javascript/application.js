// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

const measurementId = document.querySelector('meta[name="ga4-measurement-id"]')?.content

window.addEventListener("storage", event => {
	if (event.key !== "parkback_privacy_updated" || !event.newValue) return
	if (measurementId) window["ga-disable-" + measurementId] = true
	window.location.reload()
})

document.addEventListener("turbo:load", () => {
	if (!document.querySelector('meta[name="privacy-choices-updated"]')) return
	try {
		window.localStorage.setItem("parkback_privacy_updated", String(Date.now()))
	} catch {}
})

function analyticsUrl(value) {
	try {
		const url = new URL(value)
		const pathname = url.pathname.replace(/\/parking_locations\/\d+/g, "/parking_locations/spot")
		return url.origin + pathname
	} catch {
		return ""
	}
}

if (measurementId) {
	window.dataLayer = window.dataLayer || []
	window.gtag = function() { window.dataLayer.push(arguments) }
	window.gtag("js", new Date())
	window.gtag("config", measurementId, {
		send_page_view: false,
		allow_google_signals: false,
		allow_ad_personalization_signals: false,
		page_location: analyticsUrl(window.location.href),
		page_referrer: analyticsUrl(document.referrer)
	})

	let previousUrl = analyticsUrl(document.referrer)
	document.addEventListener("turbo:load", () => {
		const pageUrl = analyticsUrl(window.location.href)
		window.gtag("event", "page_view", {
			send_to: measurementId,
			page_location: pageUrl,
			page_referrer: previousUrl,
			page_title: document.title
		})
		previousUrl = pageUrl
	})
}
