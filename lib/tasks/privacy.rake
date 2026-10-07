namespace :privacy do
  desc "Permanently delete parking records and photos older than seven days"
  task purge_expired: :environment do
    ParkingLocation.purge_expired!
  end
end
