class PagesController < ApplicationController
  include OebbTransitSupport

  skip_before_action :authenticate_user!, only: [:home, :delays, :line_delays]
  before_action :set_city, only: [:delays, :line_delays]

  def home
  end

  def delays
    @latest_at = LineHealthSummary.latest_timestamp_for(@city)
    return unless @latest_at

    range_start = 24.hours.ago
    @current_health = LineHealthSummary.current_for(@city).order(:category, :line)
    all_summaries = LineHealthSummary.for_city(@city).in_range(range_start, Time.current)

    # Network-wide on-time rate
    total_snapshots = all_summaries.count
    ok_snapshots = all_summaries.where(status: "ok").count
    @network_ontime = total_snapshots > 0 ? (ok_snapshots.to_f / total_snapshots * 100).round(1) : 100

    # Network delay trend (area chart)
    @delay_over_time = all_summaries
      .group_by_period(:minute, :recorded_at, n: 5)
      .average(:avg_delay_seconds)
      .transform_values { |v| ((v || 0) / 60.0).round(1) }

    # Per-line reliability ranking
    total_by_line = all_summaries.group(:line).count
    ok_by_line = all_summaries.where(status: "ok").group(:line).count
    avg_delay_by_line = all_summaries.group(:line).average(:avg_delay_seconds)

    @line_rankings = total_by_line.map { |line, total|
      ok = ok_by_line[line] || 0
      score = total > 0 ? (ok.to_f / total * 100).round(1) : 100
      avg_delay = ((avg_delay_by_line[line] || 0) / 60.0).round(1)
      meta = all_summaries.where(line: line).pick(:category, :category_color)
      { line: line, score: score, avg_delay: avg_delay, category: meta&.first, color: meta&.last }
    }.sort_by { |r| r[:score] }

    # Top bottleneck stations for this city
    @top_bottlenecks = StopDelayRecord
      .joins(:transit_snapshot)
      .where(stop_delay_records: { city: @city })
      .where(transit_snapshots: { fetched_at: range_start.. })
      .where("stop_delay_records.delay_seconds > 0")
      .group(:stop_name, :line)
      .having("COUNT(*) >= 5")
      .order("avg_delay DESC")
      .limit(8)
      .pluck(
        :stop_name, :line,
        Arel.sql("ROUND(AVG(stop_delay_records.delay_seconds)) as avg_delay"),
        Arel.sql("COUNT(*) as occurrences")
      )

    # Worst lines right now (for the headline)
    @worst_now = @current_health.select(&:delayed?).sort_by { |l| -l.max_delay_seconds }.first(5)
  end

  def line_delays
    @line = params[:line]
    range_start = 24.hours.ago

    @line_info = LineHealthSummary.current_for(@city).find_by(line: @line)
    return redirect_to(delays_path(city: @city), alert: "Line not found") unless @line_info

    # Reliability
    line_scope = LineHealthSummary.for_city(@city).for_line(@line).in_range(range_start, Time.current)
    total = line_scope.count
    ok = line_scope.where(status: "ok").count
    @reliability = total > 0 ? (ok.to_f / total * 100).round(1) : 100
    @grade = reliability_grade(@reliability)

    # Station bottleneck data
    @stop_order = ordered_stops_for_line(@line)
    @station_delays_1d = station_delay_profile(@line, 24.hours.ago, @stop_order)
    @station_delays_7d = station_delay_profile(@line, 7.days.ago, @stop_order)

    # Worst station (for auto-generated insight)
    @worst_station = @station_delays_1d.max_by { |_, avg, _, _, _| avg.to_f }

    # Delay trend
    @delay_trend = line_scope
      .group_by_period(:minute, :recorded_at, n: 5)
      .maximum(:max_delay_seconds)
      .transform_values { |v| ((v || 0) / 60.0).round(1) }

    @avg_trend = line_scope
      .group_by_period(:minute, :recorded_at, n: 5)
      .average(:avg_delay_seconds)
      .transform_values { |v| ((v || 0) / 60.0).round(1) }

    # Current vehicle count
    latest_snapshot = TransitSnapshot.latest_for(@city)
    @vehicle_count = latest_snapshot ? VehiclePosition.where(transit_snapshot: latest_snapshot, line: @line).count : 0

    # Hour-of-day pattern
    @delay_by_hour = VehiclePosition
      .joins(:transit_snapshot)
      .where(city: @city, line: @line)
      .where(transit_snapshots: { fetched_at: range_start.. })
      .where("vehicle_positions.delay_seconds > 0")
      .group(Arel.sql("EXTRACT(HOUR FROM transit_snapshots.fetched_at)::int"))
      .average(:delay_seconds)
      .sort_by(&:first)
      .to_h { |hour, avg| ["#{hour.to_i.to_s.rjust(2, '0')}:00", ((avg || 0) / 60.0).round(1)] }

    # Worst hour (for insight text)
    @worst_hour = @delay_by_hour.max_by { |_, v| v }

    # Average delay
    @avg_delay = ((line_scope.average(:avg_delay_seconds) || 0) / 60.0).round(1)
  end

  private

  def set_city
    @city = params[:city].presence || "wien"
    @city = "wien" unless CityConfig.find(@city)
    @city_config = CityConfig.find(@city)
    @cities = CityConfig.all
  end

  def reliability_grade(score)
    if score >= 95 then "A"
    elsif score >= 85 then "B"
    elsif score >= 70 then "C"
    elsif score >= 50 then "D"
    else "F"
    end
  end

  def station_delay_profile(line, since, stop_order)
    records = StopDelayRecord
      .joins(:transit_snapshot)
      .where(city: @city, line: line)
      .where(transit_snapshots: { fetched_at: since.. })

    stop_stats = records
      .group(:stop_name)
      .pluck(
        :stop_name,
        Arel.sql("ROUND(AVG(stop_delay_records.delay_seconds)) as avg_delay"),
        Arel.sql("SUM(stop_delay_records.delay_seconds) as total_delay"),
        Arel.sql("MAX(stop_delay_records.delay_seconds) as peak_delay"),
        Arel.sql("COUNT(*) as occurrences")
      )

    all_ordered = stop_order.values.flatten
    stop_stats.sort_by do |name, _, _, _, _|
      idx = all_ordered.index(name)
      idx || (all_ordered.size + name.to_s.ord)
    end
  end

  def ordered_stops_for_line(line)
    snapshot = TransitSnapshot.latest_for(@city)
    return {} unless snapshot

    records = StopDelayRecord
      .where(transit_snapshot: snapshot, city: @city, line: line)
      .where.not(journey_id: [nil, ""])
      .order(:journey_id, :stop_sequence)

    by_direction = records.group_by(&:direction)

    by_direction.transform_values do |dir_records|
      sequences = dir_records.group_by(&:journey_id).values.filter_map do |vehicle_stops|
        stops = vehicle_stops.sort_by(&:stop_sequence).map(&:stop_name).compact
        stops.presence
      end
      merge_stop_sequences(sequences)
    end
  end

  def merge_stop_sequences(sequences)
    return [] if sequences.empty?

    all_stops = sequences.flatten.uniq
    successors = Hash.new { |h, k| h[k] = Set.new }
    pred_count = Hash.new(0)

    sequences.each do |seq|
      seq.each_cons(2) do |a, b|
        unless successors[a].include?(b)
          successors[a].add(b)
          pred_count[b] += 1
        end
      end
    end

    queue = all_stops.select { |s| pred_count[s] == 0 }
    result = []

    until queue.empty?
      node = queue.shift
      result << node
      successors[node].each do |succ|
        pred_count[succ] -= 1
        queue << succ if pred_count[succ] == 0
      end
    end

    result + (all_stops - result)
  end
end
