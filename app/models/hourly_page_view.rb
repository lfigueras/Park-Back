class HourlyPageView < ApplicationRecord
  def self.record!(page, at: Time.current)
    raise ArgumentError, "Unknown page category" unless DailyPageView::PAGES.include?(page)

    hour = at.utc.beginning_of_hour
    upsert({ hour_start: hour, page: page, views: 1 }, unique_by: [ :hour_start, :page ],
      on_duplicate: Arel.sql("views = hourly_page_views.views + 1"), returning: false)
    where("hour_start < ?", hour.beginning_of_day - (DailyPageView::RETENTION_DAYS - 1).days).delete_all
  end
end
