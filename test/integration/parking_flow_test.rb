require "test_helper"

class ParkingFlowTest < ActionDispatch::IntegrationTest
  CHROME_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

  def modern_headers
    { "HTTP_USER_AGENT" => CHROME_UA }
  end

  def with_parking_photo
    Tempfile.create([ "parking", ".png" ]) do |file|
      file.binmode
      file.write(Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII="))
      file.flush
      yield Rack::Test::UploadedFile.new(file.path, "image/png")
    end
  end

  test "GPS fallback saves a private photo without a fake pin and can be exported and cleared" do
    with_parking_photo do |photo|
      assert_difference -> { ParkingLocation.count }, 1 do
        post parking_locations_path, params: {
          parking_location: { gps_unavailable: "1", photo: photo, slot: "Near the elevator" }
        }, headers: modern_headers
      end
    end
    spot = ParkingLocation.last
    assert spot.gps_unavailable?
    assert_nil spot.latitude
    assert_nil spot.longitude
    follow_redirect!
    assert_response :success
    assert_select '[data-controller="finder"][data-finder-gps-available-value="false"]'
    assert_select "[data-finder-car-lat-value]", count: 0
    assert_select "[data-finder-car-lng-value]", count: 0
    assert_select '[data-finder-target="map"]', count: 0
    assert_select '[data-finder-target="distance"]', count: 0
    assert_select 'button[data-action="finder#refreshPosition"]', count: 0
    assert_select 'script[src*="unpkg.com"]', count: 0
    assert_select 'img[alt="Saved parking photo"]', count: 1
    assert_includes response.body, "Saved without GPS"
    get photo_parking_location_path(spot), headers: modern_headers
    assert_response :success
    assert_equal "image/png", response.media_type
    other = open_session
    other.get photo_parking_location_path(spot), headers: modern_headers
    other.assert_redirected_to root_path
    get privacy_data_path, headers: modern_headers
    exported = JSON.parse(response.body).fetch("parking_locations").first
    assert_equal true, exported["gps_unavailable"]
    assert_nil exported["latitude"]
    blob = spot.photo.blob
    assert_difference -> { ParkingLocation.count }, -1 do
      delete parking_location_path(spot), headers: modern_headers
    end
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
  ensure
    spot&.destroy_with_photo! if spot && ParkingLocation.exists?(spot.id)
  end

  test "GPS fallback requires a photo even with text details" do
    assert_no_difference -> { ParkingLocation.count } do
      post parking_locations_path, params: {
        parking_location: { gps_unavailable: "1", slot: "B2-147" }
      }, headers: modern_headers
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Photo is required when GPS is unavailable"
    assert_select 'input[name="parking_location[gps_unavailable]"][value="1"]'
    assert_select 'input[type="file"][required]'
  end

  test "normal GPS mode still allows a text-only spot" do
    assert_difference -> { ParkingLocation.count }, 1 do
      post parking_locations_path, params: {
        parking_location: { latitude: 0, longitude: 0, gps_unavailable: "0", slot: "A1" }
      }, headers: modern_headers
    end
    spot = ParkingLocation.last
    assert spot.gps_available?
    assert_not spot.photo.attached?
    follow_redirect!
    assert_select '[data-finder-gps-available-value="true"]'
  end

  test "missing fallback photo does not pretend GPS is available" do
    with_parking_photo do |photo|
      post parking_locations_path, params: {
        parking_location: { gps_unavailable: "1", photo: photo }
      }, headers: modern_headers
    end
    spot = ParkingLocation.last
    spot.photo.blob.service.delete(spot.photo.blob.key)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "This spot was saved without GPS"
    assert_select 'img[alt="Saved parking photo"]', count: 0
    assert_select '[data-finder-target="map"]', count: 0
  ensure
    spot&.destroy_with_photo! if spot && ParkingLocation.exists?(spot.id)
  end

  test "aggregate page views count refreshes without analytics consent" do
    2.times { get root_path, headers: modern_headers }
    assert_response :success
    assert_equal 2, DailyPageView.where(page: "save").pick(:views)
    assert_equal 2, HourlyPageView.where(page: "save").sum(:views)
    assert_equal %w[date page views], DailyPageView.column_names.sort
    assert_select 'script[src*="googletagmanager.com"]', count: 0
    get privacy_path, headers: modern_headers
    assert_includes response.body, "Separately from Google Analytics, we count daily and hourly page views"
    assert_equal 2, DailyPageView.sum(:views)
  end

  test "aggregate counts skip redirects and count the final find page" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.585, longitude: 121.056, slot: "counter-test" }
    }, headers: modern_headers
    assert_equal 0, DailyPageView.count
    get root_path, headers: modern_headers
    assert_response :redirect
    assert_equal 0, DailyPageView.count
    follow_redirect!
    assert_equal 1, DailyPageView.where(page: "find").pick(:views)
    assert_equal 1, HourlyPageView.where(page: "find").sum(:views)
    assert_equal 1, DailyPageView.sum(:views)
  end

  test "aggregate counts exclude HEAD requests bots and non-parking pages" do
    head root_path, headers: modern_headers
    assert_response :success
    get root_path, headers: modern_headers.merge("HTTP_USER_AGENT" => "#{CHROME_UA} ExampleCrawler")
    assert_response :success
    get privacy_path, headers: modern_headers
    get "/up", headers: modern_headers
    get "/parking_locations/99999999", headers: modern_headers
    assert_equal 0, DailyPageView.count
    assert_equal 0, HourlyPageView.count
  end

  test "daily and hourly view counts share one timestamp across UTC midnight" do
    travel_to Time.utc(2026, 10, 8, 23, 59, 59) do
      get root_path, headers: modern_headers
    end
    travel_to Time.utc(2026, 10, 9, 0, 0, 1) do
      get root_path, headers: modern_headers
    end
    assert_equal [ Date.new(2026, 10, 8), Date.new(2026, 10, 9) ], DailyPageView.order(:date).pluck(:date)
    assert_equal [ Time.utc(2026, 10, 8, 23), Time.utc(2026, 10, 9, 0) ],
      HourlyPageView.order(:hour_start).pluck(:hour_start)
  end

  test "hourly counter failure rolls back the daily increment without breaking the form" do
    previous_recorder = HourlyPageView.method(:record!)
    HourlyPageView.define_singleton_method(:record!) do |_page, **_options|
      raise ActiveRecord::ConnectionNotEstablished
    end
    get root_path, headers: modern_headers
    assert_response :success
    assert_equal 0, DailyPageView.count
    assert_equal 0, HourlyPageView.count
  ensure
    HourlyPageView.define_singleton_method(:record!, previous_recorder) if previous_recorder
  end

  test "counter failure does not prevent using the parking form" do
    previous_recorder = DailyPageView.method(:record!)
    DailyPageView.define_singleton_method(:record!) do |_page, **_options|
      raise ActiveRecord::ConnectionNotEstablished
    end
    get root_path, headers: modern_headers
    assert_response :success
    assert_select "[data-controller=locator]"
  ensure
    DailyPageView.define_singleton_method(:record!, previous_recorder) if previous_recorder
  end

  test "root shows the save form when no car is saved" do
    get root_path, headers: modern_headers
    assert_response :success
    assert_select "[data-controller=locator]"
  end

  test "release pages enforce a restricted content security policy" do
    get root_path, headers: modern_headers
    assert_response :success
    policy = response.headers["Content-Security-Policy"]
    assert_includes policy, "default-src 'self'"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "frame-ancestors 'none'"
    assert_includes policy, "form-action 'self'"
    script_policy = policy.split(";").find { |directive| directive.strip.start_with?("script-src ") }
    assert_not_includes script_policy, "'unsafe-inline'"
    assert_not_includes script_policy, "'unsafe-eval'"
    assert_includes script_policy, "'nonce-"
    assert_select 'script[type="importmap"][nonce]'
    assert_select 'script[type="module"][nonce]'

    get privacy_path, headers: modern_headers
    assert_response :success
    assert response.headers["Content-Security-Policy"].present?
  end

  test "privacy information is next to the location button without a blocking introduction" do
    get root_path, headers: modern_headers
    assert_response :success
    assert_select "#privacy-introduction", count: 0
    assert_select 'button[data-action="locator#locate"][aria-describedby="location-privacy-note"]'
    assert_select "#location-privacy-note" do
      assert_select 'a[href="/privacy"][data-turbo="false"]', "Turn maps off"
    end
    assert_includes response.body, "OpenStreetMap receives your IP address and map area."
    assert_select 'script[src*="googletagmanager.com"]', count: 0
    assert_select 'script[src*="unpkg.com"]', count: 1
  end

  test "maps are shown by default without requesting GPS or enabling analytics" do
    get root_path, headers: modern_headers
    assert_response :success
    assert_select '[data-locator-maps-declined-value="false"]'
    assert_select '[data-locator-target="map"]:not(.hidden)'
    assert_select '[data-locator-target="status"]', "Location not requested"
    assert_select 'script[src*="unpkg.com"]', count: 1
    assert_select 'script[src*="googletagmanager.com"]', count: 0

    patch privacy_preferences_path, params: {}, headers: modern_headers
    follow_redirect!
    assert_select '[data-locator-maps-declined-value="true"]'
    assert_select '[data-locator-target="map"].hidden'
    assert_select 'script[src*="unpkg.com"]', count: 0
  end

  test "privacy and parking forms work with CSRF protection enabled" do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    origin_headers = modern_headers.merge("HTTP_ORIGIN" => "http://www.example.com")

    get privacy_path, headers: modern_headers
    assert_response :success
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    token = Nokogiri::HTML(response.body).at_css('form[action="/privacy/preferences"] input[name="authenticity_token"]')["value"]
    patch privacy_preferences_path, params: { authenticity_token: token, maps: "1" }, headers: origin_headers
    assert_redirected_to root_path
    follow_redirect!
    assert_select "[data-controller=locator]"
    assert_includes response.body, "Privacy choices saved."
    get privacy_path, headers: modern_headers
    assert_select 'input[name="maps"][checked]', count: 1

    get root_path, headers: modern_headers
    assert_response :success
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    token = Nokogiri::HTML(response.body).at_css('form[action="/parking_locations"] input[name="authenticity_token"]')["value"]
    post parking_locations_path, params: {
      authenticity_token: token,
      parking_location: { latitude: 14.5, longitude: 121.0, slot: "csrf-test-slot" }
    }, headers: origin_headers
    assert_redirected_to parking_location_path(ParkingLocation.last)
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  test "location-button map permission does not grant analytics consent" do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get root_path, headers: modern_headers
    assert_select '[data-locator-map-permission-url-value="/privacy/maps"]'
    assert_select '[data-locator-target="map"]:not(.hidden)'
    assert_select 'script[src*="unpkg.com"]', count: 1
    assert_includes response.body, "OpenStreetMap receives your IP address and map area."

    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    headers = modern_headers.merge("HTTP_ACCEPT" => "application/json",
      "HTTP_X_CSRF_TOKEN" => token, "HTTP_ORIGIN" => "http://www.example.com")
    patch privacy_maps_path, headers: headers
    assert_response :success
    assert_equal true, JSON.parse(response.body)["maps"]
    get privacy_path, headers: modern_headers
    assert_select 'input[name="maps"][checked]', count: 1
    assert_select 'input[name="analytics"][checked]', count: 0

    patch privacy_preferences_path, params: { analytics: "1", maps: "0" }, headers: headers
    patch privacy_maps_path, headers: headers
    assert_response :success
    assert_equal false, JSON.parse(response.body)["maps"]
    get privacy_path, headers: modern_headers
    assert_select 'input[name="analytics"][checked]', count: 1
    assert_select 'input[name="maps"][checked]', count: 0
    get root_path, headers: modern_headers
    assert_select '[data-locator-maps-declined-value="true"]'
    assert_select 'script[src*="unpkg.com"]', count: 0
    assert_includes response.body, "Maps are off by your choice. GPS still works."
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
  end

  test "saving privacy choices returns home and preserves notification for an existing spot" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.5, longitude: 121.0, slot: "saved-spot" }
    }, headers: modern_headers
    record = ParkingLocation.last

    patch privacy_preferences_path, params: { maps: "1" }, headers: modern_headers
    assert_redirected_to root_path
    follow_redirect!
    assert_redirected_to parking_location_path(record)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Privacy choices saved."
    assert_select 'meta[name="privacy-choices-updated"]', count: 1
    assert_select '[data-finder-target="map"]', count: 1
  end

  test "admin photo gallery routes do not exist" do
    %w[/admin/photos /admin/photos/1].each do |path|
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path(path, method: :get)
      end
    end
  end

  test "browser identity is HttpOnly and parking details are filtered from logs" do
    get root_path, headers: modern_headers
    assert_response :success
    assert_match(/httponly/i, response.headers["set-cookie"].to_s)
    assert_match(/samesite=lax/i, response.headers["set-cookie"].to_s)
    assert_includes response.headers["Cache-Control"], "no-store"

    fields = %w[latitude longitude accuracy mall floor section slot landmark photo browser_token]
    params = { "parking_location" => fields.to_h { |field| [ field, "private audit sample" ] } }
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)
    fields.each { |field| assert_equal "[FILTERED]", filtered["parking_location"][field] }
  end

  test "only the owning browser can download a parking photo and public blob routes are disabled" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.5, longitude: 121.0, slot: "A1" }
    }, headers: modern_headers
    parking_location = ParkingLocation.last
    photo_data = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")
    parking_location.photo.attach(io: StringIO.new(photo_data), filename: "parking.png", content_type: "image/png")

    get photo_parking_location_path(parking_location), headers: modern_headers
    assert_response :success
    assert_equal photo_data, response.body.b
    assert_includes response.headers["Cache-Control"], "no-store"

    other = open_session
    other.get photo_parking_location_path(parking_location), headers: modern_headers
    other.assert_redirected_to root_path
    other.assert_not_equal photo_data, other.response.body.b
    assert_not Rails.application.config.active_storage.draw_routes
    assert_not Rails.application.routes.routes.any? { |route| route.path.spec.to_s.start_with?("/rails/active_storage/") }
  ensure
    parking_location&.photo&.purge
  end

  test "google analytics loads only in configured production" do
    previous_measurement_id = ENV["GA4_MEASUREMENT_ID"]
    previous_environment = Rails.env
    ENV["GA4_MEASUREMENT_ID"] = "G-TEST123456"
    script_url = "https://www.googletagmanager.com/gtag/js?id=G-TEST123456"

    get root_path, headers: modern_headers
    assert_select "script[src=?]", script_url, count: 0
    assert_select 'meta[name="ga4-measurement-id"]', count: 0

    Rails.env = "production"
    get root_path, headers: modern_headers
    assert_response :success
    assert_select "script[src=?]", script_url, count: 0
    assert_select 'link[href*="unpkg.com"]', count: 1

    patch privacy_preferences_path, params: { analytics: "1", maps: "1" }, headers: modern_headers
    assert_redirected_to root_path
    get root_path, headers: modern_headers
    assert_select "script[src=?][async]", script_url, count: 1
    assert_select 'meta[name="ga4-measurement-id"][content="G-TEST123456"]', count: 1
    assert_not_includes response.body, "plausible"

    ENV.delete("GA4_MEASUREMENT_ID")
    get root_path, headers: modern_headers
    assert_select 'script[src^="https://www.googletagmanager.com/"]', count: 0
    assert_select 'meta[name="ga4-measurement-id"]', count: 0

    ENV["GA4_MEASUREMENT_ID"] = "invalid-measurement-id"
    get root_path, headers: modern_headers
    assert_select 'script[src^="https://www.googletagmanager.com/"]', count: 0
    assert_select 'meta[name="ga4-measurement-id"]', count: 0
  ensure
    Rails.env = previous_environment
    ENV["GA4_MEASUREMENT_ID"] = previous_measurement_id
  end

  test "privacy choices can be refused and withdrawn without loading optional services" do
    previous_environment = Rails.env
    previous_measurement_id = ENV["GA4_MEASUREMENT_ID"]
    Rails.env = "production"
    ENV["GA4_MEASUREMENT_ID"] = "G-TEST123456"
    get privacy_path, headers: modern_headers
    assert_response :success
    assert_select 'a[href="mailto:lovelyfigueras@gmail.com"]'
    assert_select 'input[name="analytics"][checked]', count: 0
    assert_select 'input[name="maps"][checked]', count: 1
    assert_select 'script[src*="googletagmanager.com"]', count: 0
    assert_select 'script[src*="unpkg.com"]', count: 0

    patch privacy_preferences_path, params: { analytics: "1", maps: "1" }, headers: modern_headers
    get root_path, headers: modern_headers
    assert_select 'script[src*="googletagmanager.com"]', count: 1
    assert_select 'script[src*="unpkg.com"]', count: 1

    cookies["_ga"] = "dummy-analytics-cookie"
    cookies["_ga_TEST123456"] = "dummy-stream-cookie"
    patch privacy_preferences_path, params: {}, headers: modern_headers
    assert cookies["_ga"].blank?
    assert cookies["_ga_TEST123456"].blank?
    assert_match(/_ga=;.*max-age=0/i, Array(response.headers["set-cookie"]).join("\n"))
    follow_redirect!
    assert_select 'meta[name="privacy-choices-updated"]', count: 1
    get root_path, headers: modern_headers
    assert_response :success
    assert_select 'script[src*="googletagmanager.com"]', count: 0
    assert_select 'script[src*="unpkg.com"]', count: 0
    assert_select 'a[href="/privacy"]'
  ensure
    Rails.env = previous_environment
    ENV["GA4_MEASUREMENT_ID"] = previous_measurement_id
  end

  test "privacy export and deletion include only the owning browser's data" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.5, longitude: 121.0, slot: "private-slot" }
    }, headers: modern_headers
    own_record = ParkingLocation.last
    other_record = ParkingLocation.create!(latitude: 15, longitude: 122,
      browser_token: "another-browser", saved_at: Time.current, vehicle_type: "car", slot: "other-slot")
    photo_data = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")
    own_record.photo.attach(io: StringIO.new(photo_data), filename: "parking.png", content_type: "image/png")
    blob = own_record.photo.blob

    get privacy_data_path, headers: modern_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal [ own_record.id ], data["parking_locations"].map { |record| record["id"] }
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_not_includes response.body, "browser_token"
    assert_not_includes response.body, "other-slot"

    delete privacy_data_path, headers: modern_headers
    assert_redirected_to privacy_path
    assert_not ParkingLocation.exists?(own_record.id)
    assert ParkingLocation.exists?(other_record.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
  ensure
    own_record&.photo&.purge if own_record&.persisted? && ParkingLocation.exists?(own_record.id)
  end

  test "expired records are removed and temporary production storage cannot accept new photos" do
    record = ParkingLocation.create!(latitude: 14.5, longitude: 121.0,
      browser_token: "expired-browser", saved_at: 8.days.ago, vehicle_type: "car", slot: "old-slot")
    get root_path, headers: modern_headers
    assert_response :success
    assert_not ParkingLocation.exists?(record.id)

    previous_environment = Rails.env
    Rails.env = "production"
    assert_not ParkingLocation.photo_uploads_available?
    get root_path, headers: modern_headers
    assert_select 'input[type="file"]', count: 0
    assert_includes response.body, "Photo uploads are temporarily unavailable"
    new_record = ParkingLocation.new(latitude: 14.5, longitude: 121.0,
      browser_token: "new-browser", saved_at: Time.current, vehicle_type: "car", slot: "new-slot")
    photo_data = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")
    new_record.photo.attach(io: StringIO.new(photo_data), filename: "parking.png", content_type: "image/png")
    assert_not new_record.valid?
    assert new_record.errors[:photo].any?
  ensure
    Rails.env = previous_environment if previous_environment
  end

  test "root includes social sharing metadata" do
    get root_path, headers: modern_headers

    assert_response :success
    assert_select 'meta[property="og:site_name"][content="ParkBack"]'
    assert_select "title", "ParkBack | Save your parking location"
    assert_select 'meta[property="og:title"][content="ParkBack | Save your parking location"]'
    assert_select 'link[rel="canonical"][href="http://www.example.com/"]'
    assert_select "h1", "Where did you park?"
    assert_includes response.body, "Save your parking spot and find your way back."
    assert_select 'meta[name="robots"][content*="noindex"]', count: 0
    assert_select 'meta[property="og:description"]'
    assert_select 'meta[property="og:image"][content=?]', "http://www.example.com/parkback-share.png"
    assert_select 'meta[name="twitter:card"][content="summary_large_image"]'
    assert_select 'link[rel="icon"][href="/icon.png?v=2"]'
    assert_select 'link[rel="icon"][href="/icon.svg?v=2"]'
  end

  test "saving a spot then visiting root redirects to find-my-car" do
    assert_difference -> { ParkingLocation.count }, 1 do
      post parking_locations_path, params: {
        parking_location: {
          latitude: 14.585,
          longitude: 121.056,
          accuracy: 12,
          mall: "SM Megamall",
          floor: "B2",
          slot: "B2-147"
        }
      }, headers: modern_headers
    end
    created = ParkingLocation.last
    assert_redirected_to parking_location_path(created)

    follow_redirect!
    assert_select '[data-controller="flash"][data-turbo-temporary][role="status"] [data-flash-message]', text: "Parking spot saved!"
    assert_select ".flash-stack[data-turbo-temporary]", count: 1
    assert_select '[data-controller="flash"][data-flash-delay-value="3000"] button[aria-label="Dismiss notification"]', count: 1

    # Same browser (cookies carried over) is redirected to its car.
    get root_path, headers: modern_headers
    assert_redirected_to parking_location_path(created)

    get parking_location_path(created), headers: modern_headers
    assert_response :success
    assert_select 'meta[name="robots"][content="noindex, nofollow"]'
    assert_select "[data-controller=finder]"
    assert_match "SM Megamall", response.body
  end

  test "a different browser cannot see another browser's car" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.585, longitude: 121.056, slot: "B2-147" }
    }, headers: modern_headers
    created = ParkingLocation.last

    # New session == new browser token, no shared cookies.
    other = open_session
    other.get parking_location_path(created), headers: modern_headers
    other.assert_redirected_to root_path
    other.follow_redirect!
    other.assert_select '.flash-stack [role="alert"][data-flash-delay-value="3000"] [data-flash-message]',
      text: "That parking record is no longer available."
    other.assert_select '[role="alert"] button[aria-label="Dismiss notification"]', count: 1
  end

  test "returning after hours preserves the spot even when its photo file disappears" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.5, longitude: 121.0, slot: "long-stay" }
    }, headers: modern_headers
    record = ParkingLocation.last
    photo_data = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")
    record.photo.attach(io: StringIO.new(photo_data), filename: "parking.png", content_type: "image/png")

    travel_to 12.hours.from_now do
      get root_path, headers: modern_headers
      assert_redirected_to parking_location_path(record)
      follow_redirect!
      assert_response :success
      assert_select '[data-finder-car-lat-value="14.5"][data-finder-car-lng-value="121.0"]'
      assert_select "img[src=?]", photo_parking_location_path(record), count: 1

      record.photo.blob.service.delete(record.photo.blob.key)
      get parking_location_path(record), headers: modern_headers
      assert_response :success
      assert_select "img[src=?]", photo_parking_location_path(record), count: 0
      assert_includes response.body, "Photo file is unavailable."
      assert_select "time[datetime=?]", record.saved_at.iso8601
      assert_equal [ 14.5, 121.0 ], [ record.reload.latitude, record.longitude ]

      get photo_parking_location_path(record), headers: modern_headers
      assert_response :not_found
    end
  ensure
    record&.photo&.purge
  end

  test "clearing a saved spot deletes it" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.585, longitude: 121.056, slot: "B2-147" }
    }, headers: modern_headers
    created = ParkingLocation.last
    photo_data = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")
    created.photo.attach(io: StringIO.new(photo_data), filename: "parking.png", content_type: "image/png")
    blob = created.photo.blob

    get parking_location_path(created), headers: modern_headers
    assert_includes response.body, "deletes this spot's location, details and photo."

    assert_difference -> { ParkingLocation.count }, -1 do
      delete parking_location_path(created), headers: modern_headers
    end
    assert_redirected_to root_path
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
    follow_redirect!
    assert_includes response.body, "Your saved spot and photo have been deleted."
    assert_select '[data-controller="flash"][data-turbo-temporary][role="status"]', count: 1
    assert_includes response.body, "Uncleared spots expire after seven days."
  ensure
    created&.photo&.purge if created && ParkingLocation.exists?(created.id)
  end

  test "clearing a motorcycle shows a motorcycle-specific notice" do
    post parking_locations_path, params: {
      parking_location: {
        latitude: 14.585,
        longitude: 121.056,
        slot: "B2-147",
        vehicle_type: "motorcycle"
      }
    }, headers: modern_headers
    created = ParkingLocation.last

    delete parking_location_path(created), headers: modern_headers
    assert_redirected_to root_path
    follow_redirect!

    assert_response :success
    assert_match "glad you found your motorcycle!", response.body
    assert_select '[data-controller="flash"][role="status"] [data-flash-message]',
      text: "Nice \u2014 glad you found your motorcycle! Your saved spot has been deleted."
  end

  test "saving is rejected when no detail is provided" do
    assert_no_difference -> { ParkingLocation.count } do
      post parking_locations_path, params: {
        parking_location: { latitude: 14.585, longitude: 121.056 }
      }, headers: modern_headers
    end
    assert_response :unprocessable_entity
  end

  test "vehicle type is saved and shown" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.585, longitude: 121.056, slot: "A1", vehicle_type: "motorcycle" }
    }, headers: modern_headers
    created = ParkingLocation.last
    assert_equal "motorcycle", created.vehicle_type

    get parking_location_path(created), headers: modern_headers
    assert_match "Find your motorcycle", response.body
  end

  test "invalid vehicle type is rejected" do
    assert_no_difference -> { ParkingLocation.count } do
      post parking_locations_path, params: {
        parking_location: { latitude: 14.585, longitude: 121.056, slot: "A1", vehicle_type: "spaceship" }
      }, headers: modern_headers
    end
    assert_response :unprocessable_entity
  end
end
