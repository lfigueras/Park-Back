require "test_helper"

class DailyPageViewTest < ActiveSupport::TestCase
  test "stores only aggregate fields and increments one row per page per day" do
    assert_equal %w[date page views], DailyPageView.column_names.sort
    DailyPageView.record!("save")
    DailyPageView.record!("save")
    DailyPageView.record!("find")
    assert_equal 2, DailyPageView.count
    assert_equal 2, DailyPageView.where(page: "save").pick(:views)
    assert_equal 1, DailyPageView.where(page: "find").pick(:views)
  end

  test "uses UTC dates and keeps separate daily totals" do
    travel_to Time.utc(2026, 10, 8, 23, 59) do
      DailyPageView.record!("save")
    end
    travel_to Time.utc(2026, 10, 9, 0, 1) do
      DailyPageView.record!("save")
    end
    assert_equal [ Date.new(2026, 10, 8), Date.new(2026, 10, 9) ], DailyPageView.order(:date).pluck(:date)
  end

  test "only retains the current day and previous 89 days" do
    today = Time.current.utc.to_date
    DailyPageView.create!(date: today - 90, page: "save", views: 3)
    DailyPageView.create!(date: today - 89, page: "find", views: 2)
    DailyPageView.record!("save")
    assert_not DailyPageView.exists?(date: today - 90)
    assert_equal 2, DailyPageView.where(date: today - 89).pick(:views)
  end

  test "rejects categories that could contain a parking identifier" do
    assert_raises(ArgumentError) { DailyPageView.record!("/parking_locations/123") }
    assert_equal 0, DailyPageView.count
  end
end
