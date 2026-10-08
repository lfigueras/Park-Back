class CreateHourlyPageViews < ActiveRecord::Migration[8.1]
  def change
    create_table :hourly_page_views, id: false do |table|
      table.datetime :hour_start, null: false
      table.string :page, null: false
      table.bigint :views, null: false, default: 0
    end
    add_index :hourly_page_views, [ :hour_start, :page ], unique: true
    add_check_constraint :hourly_page_views, "views >= 0", name: "hourly_page_views_nonnegative"
    add_check_constraint :hourly_page_views, "page IN ('save', 'find')", name: "hourly_page_views_known_page"
    add_check_constraint :hourly_page_views,
      "EXTRACT(MINUTE FROM hour_start) = 0 AND EXTRACT(SECOND FROM hour_start) = 0",
      name: "hourly_page_views_whole_hour"
  end
end
