class PrivacyController < ApplicationController
  before_action :prevent_caching

  def show
  end

  def export
    records = ParkingLocation.for_token(browser_token).active.with_attached_photo.order(saved_at: :desc)
    data = records.map do |record|
      record.as_json(only: %i[id latitude longitude accuracy vehicle_type mall floor section slot landmark saved_at]).merge(
        "photo_url" => record.photo.attached? ? photo_parking_location_url(record) : nil)
    end
    send_data JSON.pretty_generate({ generated_at: Time.current.iso8601, parking_locations: data }),
      type: "application/json", disposition: :attachment, filename: "parkback-data.json"
  end

  def destroy
    ParkingLocation.for_token(browser_token).each(&:destroy_with_photo!)
    cookies.delete(:parkback_token, path: "/")
    cookies.delete(:parkback_privacy, path: "/")
    clear_analytics_cookies
    flash[:privacy_choices_changed] = true
    redirect_to privacy_path, notice: "Your browser's parking records and photos have been deleted. Optional services are off.", status: :see_other
  end

  def update
    cookies.signed[:parkback_privacy] = {
      value: {
        version: ParkingLocation::PRIVACY_NOTICE_VERSION,
        analytics: params[:analytics] == "1",
        maps: params[:maps] == "1",
        chosen_at: Time.current.iso8601
      },
      expires: 180.days.from_now, httponly: true, secure: request.ssl?, same_site: :lax
    }
    clear_analytics_cookies if params[:analytics] != "1"
    flash[:privacy_choices_changed] = true
    redirect_to privacy_path, notice: "Privacy choices saved.", status: :see_other
  end

  private

  def clear_analytics_cookies
    request.cookies.keys.grep(/\A_ga(?:_|\z)/).each do |name|
      response.delete_cookie(name, path: "/")
      parts = request.host.split(".")
      (0...(parts.length - 1)).each do |index|
        response.delete_cookie(name, path: "/", domain: parts[index..].join("."))
      end
    end
  end

  def prevent_caching
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
