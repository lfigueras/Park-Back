class CreateDailyPageViews < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_page_views, id: false do |table|
      table.date :date, null: false
      table.string :page, null: false
      table.bigint :views, null: false, default: 0
    end
    add_index :daily_page_views, [ :date, :page ], unique: true
    add_check_constraint :daily_page_views, "views >= 0", name: "daily_page_views_nonnegative"
    add_check_constraint :daily_page_views, "page IN ('save', 'find')", name: "daily_page_views_known_page"
  end
end
