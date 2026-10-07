require "test_helper"

class ParkingFlowTest < ActionDispatch::IntegrationTest
  CHROME_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

  def modern_headers
    { "HTTP_USER_AGENT" => CHROME_UA }
  end

  test "root shows the save form when no car is saved" do
    get root_path, headers: modern_headers
    assert_response :success
    assert_select "[data-controller=locator]"
  end

  test "google analytics loads only in configured production" do
    previous_measurement_id = ENV["GA4_MEASUREMENT_ID"]
    previous_environment = Rails.env
    ENV["GA4_MEASUREMENT_ID"] = "G-TEST123456"
    script_url = "https://www.googletagmanager.com/gtag/js?id=G-TEST123456"

    get root_path, headers: modern_headers
    assert_select 'script[src=?]', script_url, count: 0
    assert_select 'meta[name="ga4-measurement-id"]', count: 0

    Rails.env = "production"
    get root_path, headers: modern_headers
    assert_response :success
    assert_select 'script[src=?][async]', script_url, count: 1
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
