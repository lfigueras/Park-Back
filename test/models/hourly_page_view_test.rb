require "test_helper"

class HourlyPageViewTest < ActiveSupport::TestCase
  test "stores whole UTC hours without individual timestamps or identifiers" do
    assert_equal %w[hour_start page views], HourlyPageView.column_names.sort
    HourlyPageView.record!("save", at: Time.utc(2026, 10, 8, 3, 17, 42))
    HourlyPageView.record!("save", at: Time.utc(2026, 10, 8, 3, 59, 59))
    HourlyPageView.record!("find", at: Time.utc(2026, 10, 8, 3, 22))
    assert_equal 2, HourlyPageView.count
    assert_equal 2, HourlyPageView.where(page: "save").pick(:views)
    assert_equal Time.utc(2026, 10, 8, 3), HourlyPageView.where(page: "save").pick(:hour_start)
  end

  test "keeps separate hours and handles UTC midnight" do
    HourlyPageView.record!("save", at: Time.utc(2026, 10, 8, 23, 59))
    HourlyPageView.record!("save", at: Time.utc(2026, 10, 9, 0, 1))
    assert_equal [ Time.utc(2026, 10, 8, 23), Time.utc(2026, 10, 9, 0) ],
      HourlyPageView.order(:hour_start).pluck(:hour_start)
  end

  test "cleans older hours without changing legacy daily totals" do
    now = Time.utc(2026, 10, 8, 12)
    cutoff = now.beginning_of_day - 89.days
    HourlyPageView.create!(hour_start: cutoff - 1.hour, page: "save", views: 3)
    HourlyPageView.create!(hour_start: cutoff, page: "find", views: 2)
    DailyPageView.create!(date: now.to_date, page: "save", views: 5)
    HourlyPageView.record!("save", at: now)
    assert_not HourlyPageView.exists?(hour_start: cutoff - 1.hour)
    assert_equal 2, HourlyPageView.where(hour_start: cutoff).pick(:views)
    assert_equal 5, DailyPageView.where(page: "save").pick(:views)
  end

  test "rejects arbitrary categories and finer timestamp buckets" do
    assert_raises(ArgumentError) { HourlyPageView.record!("/parking_locations/123") }
    assert_raises(ActiveRecord::StatementInvalid) do
      HourlyPageView.transaction(requires_new: true) do
        HourlyPageView.create!(hour_start: Time.utc(2026, 10, 8, 3, 17), page: "save", views: 1)
      end
    end
    assert_equal 0, HourlyPageView.count
  end
end
