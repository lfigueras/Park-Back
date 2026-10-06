class ParkingLocation < ApplicationRecord
  has_one_attached :photo

  VEHICLE_TYPES = %w[car motorcycle bicycle truck].freeze
  DETAIL_FIELDS = %i[mall floor section slot landmark].freeze

  validates :latitude, :longitude, :browser_token, :saved_at, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :vehicle_type, inclusion: { in: VEHICLE_TYPES }
  validate :photo_is_an_image
  validate :at_least_one_detail

  scope :for_token, ->(token) { where(browser_token: token) }

  # The active (most recent) parking session for a given browser token.
  def self.current_for(token)
    for_token(token).order(saved_at: :desc).first
  end

  private

  def photo_is_an_image
    return unless photo.attached?
    return if photo.content_type.in?(%w[image/png image/jpeg image/jpg image/webp image/heic])

    errors.add(:photo, "must be a PNG, JPEG, WEBP, or HEIC image")
  end

  # A GPS pin alone is easy to lose track of, so require at least one
  # human-readable detail (or a photo) before saving.
  def at_least_one_detail
    return if DETAIL_FIELDS.any? { |field| public_send(field).present? } || photo.attached?

    errors.add(:base, "Add at least one detail (mall, floor, section, slot, landmark, or photo) before saving.")
  end
end
