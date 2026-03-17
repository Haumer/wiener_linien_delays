class LineHealthSummary < ApplicationRecord
  include OebbTransitSupport

  STATUSES = %w[ok minor_delay major_delay disrupted].freeze

  scope :for_city, ->(city) { where(city: city) }
  scope :current, -> { where(recorded_at: latest_timestamp) }
  scope :current_for, ->(city) { for_city(city).where(recorded_at: for_city(city).maximum(:recorded_at)) }
  scope :for_line, ->(line) { where(line: line) }
  scope :in_range, ->(from, to) { where(recorded_at: from..to) }
  scope :delayed, -> { where.not(status: "ok") }
  scope :disrupted, -> { where(status: "disrupted") }

  def self.latest_timestamp
    maximum(:recorded_at)
  end

  def self.latest_timestamp_for(city)
    for_city(city).maximum(:recorded_at)
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
