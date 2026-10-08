namespace :traffic do
  desc "Report aggregate page views for the last 90 UTC days (not unique visitors)"
  task report: :environment do
    today = Time.current.utc.to_date
    rows = DailyPageView.where(date: (today - (DailyPageView::RETENTION_DAYS - 1))..today)
      .order(:date, :page).pluck(:date, :page, :views)
    puts "Date (UTC)\tPage\tViews"
    rows.each { |date, page, views| puts "#{date}\t#{page}\t#{views}" }
    puts "Total page views: #{rows.sum { |row| row[2] }} (not unique visitors)"
  end

  desc "Report hourly page views in UTC and Philippine time (not individual visits)"
  task hourly: :environment do
    now = Time.current.utc
    from = now.beginning_of_day - (DailyPageView::RETENTION_DAYS - 1).days
    rows = HourlyPageView.where(hour_start: from..now).order(:hour_start, :page)
      .pluck(:hour_start, :page, :views)
    puts "Hour (UTC)\tHour (Philippines)\tPage\tViews"
    rows.each do |hour, page, views|
      utc = hour.utc.strftime("%Y-%m-%d %H:00")
      philippines = hour.in_time_zone("Asia/Manila").strftime("%Y-%m-%d %H:00")
      puts "#{utc}\t#{philippines}\t#{page}\t#{views}"
    end
    puts "Total hourly page views: #{rows.sum { |row| row[2] }} (not unique visitors)"
    puts "Each time starts a one-hour group, not an individual visit timestamp."
    puts "Earlier daily totals have no recorded hour; hourly totals start when this feature is enabled."
  end
end
