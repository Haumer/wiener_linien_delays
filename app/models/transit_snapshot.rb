class TransitSnapshot < ApplicationRecord
  has_many :vehicle_positions, dependent: :delete_all
  has_many :stop_delay_records, dependent: :delete_all

  scope :for_city, ->(city) { where(city: city) }
  scope :recent, ->(duration = 24.hours) { where(fetched_at: duration.ago..) }

  def self.latest
    order(fetched_at: :desc).first
  end

  def self.latest_for(city)
    for_city(city).order(fetched_at: :desc).first
  end
end
