class AddVehicleTypeToParkingLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :parking_locations, :vehicle_type, :string, null: false, default: "car"
  end
end
