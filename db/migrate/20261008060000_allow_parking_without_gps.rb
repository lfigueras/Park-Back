class AllowParkingWithoutGps < ActiveRecord::Migration[8.1]
  def change
    add_column :parking_locations, :gps_unavailable, :boolean, null: false, default: false
    change_column_null :parking_locations, :latitude, true
    change_column_null :parking_locations, :longitude, true
    add_check_constraint :parking_locations,
      "(gps_unavailable = FALSE AND latitude IS NOT NULL AND longitude IS NOT NULL) OR " \
      "(gps_unavailable = TRUE AND latitude IS NULL AND longitude IS NULL AND accuracy IS NULL)",
      name: "parking_locations_coordinate_state"
  end
end
