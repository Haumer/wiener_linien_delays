class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home, :delays ]

  def home
  end

  def delays
    @current_health = LineHealthSummary.current.order(:category, :line)
    @disrupted_lines = @current_health.select(&:delayed?)
    @latest_at = LineHealthSummary.latest_timestamp

    # Stats for the last 24 hours
    range_start = 24.hours.ago
    @all_summaries = LineHealthSummary.in_range(range_start, Time.current)

    # Most delayed lines (by average of their max delays over 24h)
    @worst_lines = @all_summaries
      .group(:line, :category, :category_color)
      .order("avg_max DESC")
      .limit(10)
      .pluck(
        :line, :category, :category_color,
        Arel.sql("ROUND(AVG(max_delay_seconds)) as avg_max"),
        Arel.sql("MAX(max_delay_seconds) as peak"),
        Arel.sql("ROUND(AVG(avg_delay_seconds)) as avg_avg"),
        Arel.sql("COUNT(*) as samples")
      )

    # Delay distribution over time (for the area chart)
    @delay_over_time = @all_summaries
      .group_by_period(:minute, :recorded_at, n: 5)
      .average(:avg_delay_seconds)
      .transform_values { |v| (v / 60.0).round(1) }

    # Disruption frequency per line (how many snapshots in non-ok status)
    @disruption_frequency = @all_summaries
      .delayed
      .group(:line)
      .order(Arel.sql("COUNT(id) DESC"))
      .limit(10)
      .count("id")

    # Category breakdown
    @category_avg_delays = @all_summaries
      .group(:category)
      .average(:avg_delay_seconds)
      .transform_values { |v| (v / 60.0).round(1) }

    # Per-line detail charts (top 5 worst)
    worst_line_names = @worst_lines.first(5).map(&:first)
    @line_charts = worst_line_names.to_h do |line|
      data = LineHealthSummary.for_line(line)
        .in_range(range_start, Time.current)
        .order(:recorded_at)
        .group_by_period(:minute, :recorded_at, n: 5)
        .maximum(:max_delay_seconds)
        .transform_values { |v| (v / 60.0).round(1) }
      [line, data]
    end

    # When do delays start? Avg delay by hour of day per worst line
    @delay_by_hour = worst_line_names.first(5).to_h do |line|
      data = VehiclePosition
        .joins(:transit_snapshot)
        .where(line: line)
        .where(transit_snapshots: { fetched_at: range_start.. })
        .where("vehicle_positions.delay_seconds > 0")
        .group(Arel.sql("EXTRACT(HOUR FROM transit_snapshots.fetched_at)::int"))
        .average(:delay_seconds)
        .sort_by(&:first)
        .to_h { |hour, avg| ["#{hour.to_i.to_s.rjust(2, '0')}:00", (avg / 60.0).round(1)] }
      [line, data]
    end

    # Where do delays cluster? Top directions/areas with highest avg delay
    @delay_hotspots = VehiclePosition
      .joins(:transit_snapshot)
      .where(transit_snapshots: { fetched_at: range_start.. })
      .where("vehicle_positions.delay_seconds >= 120")
      .group(:line, :direction)
      .having("COUNT(*) >= 3")
      .order("avg_delay DESC")
      .limit(15)
      .pluck(
        :line, :direction,
        Arel.sql("ROUND(AVG(vehicle_positions.delay_seconds)) as avg_delay"),
        Arel.sql("MAX(vehicle_positions.delay_seconds) as peak_delay"),
        Arel.sql("COUNT(*) as occurrences")
      )
  end
end
