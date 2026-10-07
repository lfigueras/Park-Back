class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :purge_expired_parking_data

  helper_method :browser_token, :privacy_preferences, :maps_allowed?, :analytics_allowed?

  private

  def purge_expired_parking_data
    ParkingLocation.purge_expired!(limit: 25)
  end

  def privacy_preferences
    preferences = cookies.signed[:parkback_privacy]
    return {} unless preferences.is_a?(Hash) && preferences["version"] == ParkingLocation::PRIVACY_NOTICE_VERSION

    preferences
  end

  def maps_allowed?
    privacy_preferences["maps"] != false
  end

  def analytics_allowed?
    privacy_preferences["analytics"] == true
  end

  # A stable, per-browser identity stored in a signed permanent cookie.
  # Lets a browser "own" its parking location without any login.
  def browser_token
    token = cookies.signed[:parkback_token].presence || SecureRandom.uuid
    cookies.signed[:parkback_token] = {
      value: token, expires: 7.days.from_now, httponly: true,
      secure: request.ssl?, same_site: :lax
    }
    token
  end
end
