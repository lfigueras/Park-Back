class CreateParkingLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :parking_locations do |t|
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.float :accuracy
      t.string :mall
      t.string :floor
      t.string :section
      t.string :slot
      t.text :landmark
      t.string :browser_token, null: false
      t.datetime :saved_at, null: false

      t.timestamps
    end
    add_index :parking_locations, :browser_token
  end
end
