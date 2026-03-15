class LineHealthSummary < ApplicationRecord
  include OebbTransitSupport

  STATUSES = %w[ok minor_delay major_delay disrupted].freeze

  scope :current, -> { where(recorded_at: latest_timestamp) }
  scope :for_line, ->(line) { where(line: line) }
  scope :in_range, ->(from, to) { where(recorded_at: from..to) }
  scope :delayed, -> { where.not(status: "ok") }
  scope :disrupted, -> { where(status: "disrupted") }

  def self.latest_timestamp
    maximum(:recorded_at)
  end

  def delayed?
    status != "ok"
  end

  def delay_minutes
    (avg_delay_seconds / 60.0).round(1)
  end

  def max_delay_minutes
    (max_delay_seconds / 60.0).round(1)
  end

  def category_config
    CATEGORY_CONFIG[category] || { label: category, color: "#94a3b8" }
  end
end
