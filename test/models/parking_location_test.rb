require "test_helper"
require "open3"

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

  test "saves a photo-only spot when GPS is explicitly unavailable" do
    spot = ParkingLocation.new(base_attrs.merge(latitude: nil, longitude: nil, gps_unavailable: true))
    spot.photo.attach(io: StringIO.new(PNG), filename: "area.png", content_type: "image/png")
    assert spot.save, spot.errors.full_messages.to_sentence
    assert spot.reload.gps_unavailable?
    assert_not spot.gps_available?
    assert_nil spot.latitude
    assert_nil spot.longitude
  ensure
    spot&.photo&.purge
  end

  test "text details cannot replace the required photo without GPS" do
    spot = ParkingLocation.new(base_attrs.merge(latitude: nil, longitude: nil, gps_unavailable: true, slot: "A1"))
    assert_not spot.valid?
    assert_includes spot.errors[:photo], "is required when GPS is unavailable"
  end

  test "GPS fallback rejects leftover coordinates or accuracy" do
    [ { latitude: 0 }, { longitude: 0 }, { accuracy: 10 } ].each do |remaining|
      spot = ParkingLocation.new(base_attrs.merge(latitude: nil, longitude: nil, gps_unavailable: true).merge(remaining))
      spot.photo.attach(io: StringIO.new(PNG), filename: "area.png", content_type: "image/png")
      assert_not spot.valid?
      assert_includes spot.errors[:base], "A spot saved without GPS cannot include GPS coordinates or accuracy."
    end
  end

  test "photo does not bypass missing or invalid GPS in normal mode" do
    [ { latitude: nil }, { longitude: nil }, { latitude: 91 }, { longitude: 181 } ].each do |coordinates|
      spot = ParkingLocation.new(base_attrs.merge(coordinates))
      spot.photo.attach(io: StringIO.new(PNG), filename: "area.png", content_type: "image/png")
      assert_not spot.valid?
    end
  end

  test "photo validation still applies to GPS fallback" do
    spot = ParkingLocation.new(base_attrs.merge(latitude: nil, longitude: nil, gps_unavailable: true))
    spot.photo.attach(io: StringIO.new("not an image"), filename: "notes.txt", content_type: "text/plain")
    assert_not spot.valid?
    assert_includes spot.errors[:photo], "must be a PNG, JPEG, WEBP, or HEIC image"
  end

  test "rejects photos larger than five megabytes" do
    loc = ParkingLocation.new(base_attrs.merge(slot: "A1"))
    bytes = PNG.ljust(5.megabytes + 1, "\0")
    loc.photo.attach(io: StringIO.new(bytes), filename: "large.png", content_type: "image/png")
    assert_not loc.valid?
    assert_includes loc.errors[:photo], "must be 5 MB or smaller"
  end

  test "neon uses private path-style storage while test storage remains local" do
    assert_instance_of ActiveStorage::Service::DiskService, ActiveStorage::Blob.service
    configuration = Rails.application.config.active_storage.service_configurations.fetch("neon")
    assert_equal "S3", configuration["service"]
    assert_equal true, configuration["force_path_style"]
    assert_equal false, configuration["public"]
    assert_equal "when_required", configuration["request_checksum_calculation"]

    previous_environment = Rails.env
    previous_service = ActiveStorage::Blob.service
    stubbed = configuration.merge("access_key_id" => "test-access-key",
      "secret_access_key" => "test-secret-key", "endpoint" => "https://storage.example.invalid",
      "stub_responses" => true)
    ActiveStorage::Blob.service = ActiveStorage::Service.configure(:neon, { "neon" => stubbed })
    Rails.env = "production"
    assert ParkingLocation.photo_uploads_available?
  ensure
    Rails.env = previous_environment if previous_environment
    ActiveStorage::Blob.service = previous_service if previous_service
  end

  test "fresh production boots select neon only with complete storage settings" do
    configured = {
      "NEON_STORAGE_ENDPOINT" => "https://storage.example.invalid",
      "NEON_STORAGE_ACCESS_KEY_ID" => "test-access-key",
      "NEON_STORAGE_SECRET_ACCESS_KEY" => "test-secret-key"
    }
    script = <<~RUBY
      require "#{Rails.root}/config/environment"
      puts Rails.application.config.active_storage.service
      puts ParkingLocation.photo_uploads_available?
    RUBY

    [
      [ configured, "neon", "true" ],
      [ configured.transform_values { nil }, "local", "false" ],
      [ configured.merge("NEON_STORAGE_SECRET_ACCESS_KEY" => nil), "local", "false" ]
    ].each do |settings, service, available|
      environment = settings.merge("RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1")
      output, errors, result = Open3.capture3(environment, RbConfig.ruby, "-e", script)
      assert result.success?, errors
      assert_equal [ service, available ], output.lines.map(&:strip).last(2)
    end
  end
end
