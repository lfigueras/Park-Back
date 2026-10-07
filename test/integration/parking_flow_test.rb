require "test_helper"

class ParkingFlowTest < ActionDispatch::IntegrationTest
  CHROME_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

  def modern_headers
    { "HTTP_USER_AGENT" => CHROME_UA }
  end

  test "photo gallery fails closed without credentials and rejects unauthenticated requests" do
    previous_username = ENV["PHOTO_ADMIN_USERNAME"]
    previous_password = ENV["PHOTO_ADMIN_PASSWORD"]
    ENV.delete("PHOTO_ADMIN_USERNAME")
    ENV.delete("PHOTO_ADMIN_PASSWORD")

    get admin_photos_path, headers: modern_headers
    assert_response :not_found
    assert_equal %w[no-store private], response.headers["Cache-Control"].split(", ").sort

    ENV["PHOTO_ADMIN_USERNAME"] = "photo-admin"
    ENV["PHOTO_ADMIN_PASSWORD"] = "test-only-password"
    get admin_photos_path, headers: modern_headers
    assert_response :unauthorized

    wrong_auth = ActionController::HttpAuthentication::Basic.encode_credentials("photo-admin", "wrong-password")
    get admin_photos_path, headers: modern_headers.merge("HTTP_AUTHORIZATION" => wrong_auth)
    assert_response :unauthorized
    get admin_photo_path(1), headers: modern_headers
    assert_response :unauthorized
  ensure
    ENV["PHOTO_ADMIN_USERNAME"] = previous_username
    ENV["PHOTO_ADMIN_PASSWORD"] = previous_password
  end

  test "photo gallery and original files require admin authentication and handle missing files" do
    previous_username = ENV["PHOTO_ADMIN_USERNAME"]
    previous_password = ENV["PHOTO_ADMIN_PASSWORD"]
    previous_gallery_enabled = ENV["PHOTO_ADMIN_ENABLED"]
    previous_measurement_id = ENV["GA4_MEASUREMENT_ID"]
    previous_environment = Rails.env
    ENV["PHOTO_ADMIN_USERNAME"] = "photo-admin"
    ENV["PHOTO_ADMIN_PASSWORD"] = "test-only-password"
    ENV["PHOTO_ADMIN_ENABLED"] = "true"
    ENV["GA4_MEASUREMENT_ID"] = "G-TEST123456"
    authorization = ActionController::HttpAuthentication::Basic.encode_credentials("photo-admin", "test-only-password")
    headers = modern_headers.merge("HTTP_AUTHORIZATION" => authorization)
    parking_location = ParkingLocation.create!(latitude: 14.5, longitude: 121.0,
      browser_token: "gallery-test-browser", saved_at: Time.current, vehicle_type: "car", slot: "A1")
    photo_data = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=")
    parking_location.photo.attach(io: StringIO.new(photo_data), filename: "parking.png", content_type: "image/png")

    Rails.env = "production"
    get admin_photos_path, headers: headers
    assert_response :success
    assert_select "h1", "Saved photos"
    assert_select "img[src=?]", admin_photo_path(parking_location), count: 1
    assert_select 'meta[name="ga4-measurement-id"]', count: 0
    assert_equal %w[no-store private], response.headers["Cache-Control"].split(", ").sort
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_not_includes response.body, "gallery-test-browser"

    get admin_photo_path(parking_location), headers: headers
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal photo_data, response.body.b

    parking_location.photo.blob.service.delete(parking_location.photo.blob.key)
    get admin_photo_path(parking_location), headers: headers
    assert_response :not_found
    get admin_photos_path, headers: headers
    assert_response :success
    assert_includes response.body, "File unavailable"
    assert_select "img[src=?]", admin_photo_path(parking_location), count: 0
  ensure
    Rails.env = previous_environment
    ENV["PHOTO_ADMIN_USERNAME"] = previous_username
    ENV["PHOTO_ADMIN_PASSWORD"] = previous_password
    ENV["PHOTO_ADMIN_ENABLED"] = previous_gallery_enabled
    ENV["GA4_MEASUREMENT_ID"] = previous_measurement_id
    parking_location&.photo&.purge
  end

  test "root shows the save form when no car is saved" do
    get root_path, headers: modern_headers
    assert_response :success
    assert_select "[data-controller=locator]"
  end

  test "admin photo access is disabled by default in production" do
    previous_environment = Rails.env
    previous_gallery_enabled = ENV["PHOTO_ADMIN_ENABLED"]
    Rails.env = "production"
    ENV.delete("PHOTO_ADMIN_ENABLED")
    get admin_photos_path, headers: modern_headers
    assert_response :not_found
    get admin_photo_path(1), headers: modern_headers
    assert_response :not_found
  ensure
    Rails.env = previous_environment
    ENV["PHOTO_ADMIN_ENABLED"] = previous_gallery_enabled
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
    assert_select 'link[href*="unpkg.com"]', count: 0

    patch privacy_preferences_path, params: { analytics: "1", maps: "1" }, headers: modern_headers
    assert_redirected_to privacy_path
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
    assert_select 'input[name="maps"][checked]', count: 0
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
    assert_select "title", "ParkBack"
    assert_select 'meta[property="og:title"][content="ParkBack"]'
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

    # Same browser (cookies carried over) is redirected to its car.
    get root_path, headers: modern_headers
    assert_redirected_to parking_location_path(created)

    get parking_location_path(created), headers: modern_headers
    assert_response :success
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
  end

  test "clearing a saved spot deletes it" do
    post parking_locations_path, params: {
      parking_location: { latitude: 14.585, longitude: 121.056, slot: "B2-147" }
    }, headers: modern_headers
    created = ParkingLocation.last

    assert_difference -> { ParkingLocation.count }, -1 do
      delete parking_location_path(created), headers: modern_headers
    end
    assert_redirected_to root_path
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
