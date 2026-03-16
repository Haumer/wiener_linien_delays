class StopDelayRecord < ApplicationRecord
  belongs_to :transit_snapshot

  scope :for_line, ->(line) { where(line: line) }
  scope :delayed, -> { where("delay_seconds > 0") }
end
