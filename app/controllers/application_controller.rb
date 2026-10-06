class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :browser_token

  private

  # A stable, per-browser identity stored in a signed permanent cookie.
  # Lets a browser "own" its parking location without any login.
  def browser_token
    cookies.signed.permanent[:parkback_token] ||= SecureRandom.uuid
  end
end
