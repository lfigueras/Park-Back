class DailyPageView < ApplicationRecord
  PAGES = %w[save find].freeze
  RETENTION_DAYS = 90

  def self.record!(page, date: Time.current.utc.to_date)
    raise ArgumentError, "Unknown page category" unless PAGES.include?(page)

    upsert({ date: date, page: page, views: 1 }, unique_by: [ :date, :page ],
      on_duplicate: Arel.sql("views = daily_page_views.views + 1"), returning: false)
    where("date < ?", date - (RETENTION_DAYS - 1)).delete_all
  end
end
