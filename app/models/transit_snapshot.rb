class TransitSnapshot < ApplicationRecord
  has_many :vehicle_positions, dependent: :delete_all

  scope :recent, ->(duration = 24.hours) { where(fetched_at: duration.ago..) }

  def self.latest
    order(fetched_at: :desc).first
  end
end
