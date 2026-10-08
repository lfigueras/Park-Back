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
end
