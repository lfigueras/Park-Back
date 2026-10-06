class ParkingLocationsController < ApplicationController
  before_action :set_parking_location, only: %i[show destroy]

  # Landing page: if the browser already saved a car, jump straight to it.
  # Otherwise show the "Save Parking Location" form.
  def index
    current = ParkingLocation.current_for(browser_token)
    if current
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
  end

  def destroy
    @parking_location.destroy
    redirect_to root_path, notice: "Nice \u2014 glad you found your car!"
  end

  private

  def set_parking_location
    @parking_location = ParkingLocation.for_token(browser_token).find(params[:id])
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
