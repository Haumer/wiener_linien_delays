class VehiclePosition < ApplicationRecord
  belongs_to :transit_snapshot

  scope :delayed, -> { where("delay_seconds > 0") }
  scope :stalled, -> { where(stalled: true) }
  scope :for_line, ->(line) { where(line: line) }
end
