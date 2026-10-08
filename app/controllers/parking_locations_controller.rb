class ParkingLocationsController < ApplicationController
  before_action :set_parking_location, only: %i[show destroy photo]
  before_action :prevent_private_caching

  # Landing page: if the browser already saved a car, jump straight to it.
  # Otherwise show the "Save Parking Location" form.
  def index
    current = ParkingLocation.current_for(browser_token)
    if current
      flash.keep if flash[:privacy_choices_changed]
      redirect_to parking_location_path(current)
    else
      @parking_location = ParkingLocation.new
      render :new
    end
  end

  def new
    @parking_location = ParkingLocation.new
  end

  def create
    @parking_location = ParkingLocation.new(parking_location_params)
    @parking_location.browser_token = browser_token
    @parking_location.saved_at = Time.current

    if @parking_location.save
      redirect_to parking_location_path(@parking_location), notice: "Parking spot saved!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # "Find My Car" screen.
  def show
    attachment = @parking_location.photo
    @photo_available = attachment.attached? && attachment.blob.service.exist?(attachment.blob.key)
  end

  def photo
    return head :not_found unless @parking_location.photo.attached?

    attachment = @parking_location.photo
    send_data attachment.download, type: attachment.content_type,
      disposition: :inline, filename: "parking-photo#{attachment.filename.extension_with_delimiter}"
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  end

  def destroy
    vehicle_type = @parking_location.vehicle_type
    deletion_message = if @parking_location.photo.attached?
      "Your saved spot and photo have been deleted."
    else
      "Your saved spot has been deleted."
    end
    @parking_location.destroy_with_photo!
    redirect_to root_path, notice: "Nice \u2014 glad you found your #{vehicle_type}! #{deletion_message}"
  end

  private

  def prevent_private_caching
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
  end

  def set_parking_location
    @parking_location = ParkingLocation.for_token(browser_token).active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "That parking record is no longer available."
  end

  def parking_location_params
    params.require(:parking_location).permit(
      :latitude, :longitude, :accuracy, :vehicle_type,
      :mall, :floor, :section, :slot, :landmark, :photo
    )
  end
end
