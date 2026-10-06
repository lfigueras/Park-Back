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
