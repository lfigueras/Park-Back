require "test_helper"

class ParkingLocationTest < ActiveSupport::TestCase
  def base_attrs
    { latitude: 14.585, longitude: 121.056, browser_token: "tok", saved_at: Time.current }
  end

  # 1x1 transparent PNG.
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMEAYHgL0" \
    "rqAAAAAElFTkSuQmCC"
  )

  test "requires at least one detail" do
    loc = ParkingLocation.new(base_attrs)
    assert_not loc.valid?
    assert loc.errors[:base].any?
  end

  test "a text detail satisfies the requirement" do
    loc = ParkingLocation.new(base_attrs.merge(slot: "B2-147"))
    assert loc.valid?, loc.errors.full_messages.to_sentence
  end

  test "a photo alone satisfies the requirement" do
    loc = ParkingLocation.new(base_attrs)
    loc.photo.attach(io: StringIO.new(PNG), filename: "area.png", content_type: "image/png")
    assert loc.valid?, loc.errors.full_messages.to_sentence
  end

  test "rejects an invalid vehicle type" do
    loc = ParkingLocation.new(base_attrs.merge(slot: "A1", vehicle_type: "spaceship"))
    assert_not loc.valid?
    assert loc.errors[:vehicle_type].any?
  end
end
