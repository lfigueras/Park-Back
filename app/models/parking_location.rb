require "active_storage/service/disk_service"

class ParkingLocation < ApplicationRecord
  has_one_attached :photo

  PRIVACY_NOTICE_VERSION = "2026-10-07".freeze
  RETENTION_DAYS = 7
  VEHICLE_TYPES = %w[car motorcycle bicycle truck].freeze
  DETAIL_FIELDS = %i[mall floor section slot landmark].freeze

  validates :latitude, :longitude, :browser_token, :saved_at, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :vehicle_type, inclusion: { in: VEHICLE_TYPES }
  validate :photo_is_an_image
  validate :at_least_one_detail
  validate :photo_storage_is_durable, on: :create

  scope :for_token, ->(token) { where(browser_token: token) }
  scope :active, -> { where("saved_at > ?", RETENTION_DAYS.days.ago) }
  scope :expired, -> { where("saved_at <= ?", RETENTION_DAYS.days.ago) }

  def self.photo_uploads_available?
    !Rails.env.production? || !ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::DiskService)
  end

  def self.purge_expired!(limit: nil)
    records = expired.order(:id)
    records = records.limit(limit) if limit
    records.each(&:destroy_with_photo!)
  end

  def destroy_with_photo!
    photo.purge if photo.attached?
    destroy!
  end

  # The active (most recent) parking session for a given browser token.
  def self.current_for(token)
    for_token(token).active.order(saved_at: :desc).first
  end

  private

  def photo_storage_is_durable
    if photo.attached? && !self.class.photo_uploads_available?
      errors.add(:photo, "uploads are temporarily unavailable until durable storage is configured")
    end
  end

  def photo_is_an_image
    return unless photo.attached?
    errors.add(:photo, "must be 5 MB or smaller") if photo.byte_size > 5.megabytes
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
