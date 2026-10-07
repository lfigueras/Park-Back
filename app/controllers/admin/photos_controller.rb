module Admin
  class PhotosController < ApplicationController
    before_action :prevent_caching
    before_action :authenticate_admin

    def index
      @page = [ params[:page].to_i, 1 ].max
      photos = ParkingLocation.active.joins(:photo_attachment)
      @photo_count = photos.count
      @parking_locations = photos.with_attached_photo.order(saved_at: :desc).limit(24).offset((@page - 1) * 24)
    end

    def show
      parking_location = ParkingLocation.active.find(params[:id])
      return head :not_found unless parking_location.photo.attached?

      photo = parking_location.photo
      send_data photo.download, type: photo.content_type, disposition: :inline,
        filename: photo.filename.to_s
    rescue ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError
      head :not_found
    end

    private

    def prevent_caching
      response.headers["Cache-Control"] = "no-store, private"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    def authenticate_admin
      return head :not_found if Rails.env.production? && ENV["PHOTO_ADMIN_ENABLED"] != "true"

      username = ENV["PHOTO_ADMIN_USERNAME"].presence
      password = ENV["PHOTO_ADMIN_PASSWORD"].presence
      return head :not_found unless username && password

      authenticate_or_request_with_http_basic("ParkBack photos") do |supplied_username, supplied_password|
        username_matches = ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(supplied_username), Digest::SHA256.hexdigest(username))
        password_matches = ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(supplied_password), Digest::SHA256.hexdigest(password))
        username_matches & password_matches
      end
    end
  end
end
