class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home, :delays, :line_delays, :network, :fleet ]

  def home
  end

  def network
  end

  def fleet
    latest = TransitSnapshot.latest
    @latest_at = latest&.fetched_at

    if latest
      # Journey IDs currently active
      active_ids = VehiclePosition.where(transit_snapshot: latest).pluck(:journey_id)

      # Last known position for every journey_id seen in the last 24h
      # that is NOT in the current snapshot (= terminated)
      range_start = 24.hours.ago

      last_positions_sql = VehiclePosition
        .joins(:transit_snapshot)
        .where(transit_snapshots: { fetched_at: range_start.. })
        .where.not(journey_id: active_ids)
        .select("DISTINCT ON (vehicle_positions.journey_id) vehicle_positions.*, transit_snapshots.fetched_at AS last_seen_at")
        .order("vehicle_positions.journey_id, transit_snapshots.fetched_at DESC")

      @terminated = VehiclePosition.from(last_positions_sql, :vehicle_positions)
        .order("last_seen_at DESC")
        .limit(500)

      # Currently active fleet
      @active = VehiclePosition.where(transit_snapshot: latest).order(:category, :line)

      # Termination hotspots — cluster by approximate location (rounded to ~200m grid)
      @hotspots = VehiclePosition
        .joins(:transit_snapshot)
        .where(transit_snapshots: { fetched_at: range_start.. })
        .where.not(journey_id: active_ids)
        .group(
          Arel.sql("ROUND(CAST(vehicle_positions.lat AS numeric), 3)"),
          Arel.sql("ROUND(CAST(vehicle_positions.lng AS numeric), 3)")
        )
        .having("COUNT(*) >= 3")
        .order("termination_count DESC")
        .limit(30)
        .pluck(
          Arel.sql("ROUND(CAST(vehicle_positions.lat AS numeric), 3) as grid_lat"),
          Arel.sql("ROUND(CAST(vehicle_positions.lng AS numeric), 3) as grid_lng"),
          Arel.sql("COUNT(*) as termination_count"),
          Arel.sql("array_agg(DISTINCT vehicle_positions.line ORDER BY vehicle_positions.line) as lines")
        )

      # Terminations by hour
      @by_hour = VehiclePosition
        .joins(:transit_snapshot)
        .where(transit_snapshots: { fetched_at: range_start.. })
        .where.not(journey_id: active_ids)
        .joins("INNER JOIN (
          SELECT journey_id, MAX(transit_snapshot_id) as last_snap
          FROM vehicle_positions
          INNER JOIN transit_snapshots ON transit_snapshots.id = vehicle_positions.transit_snapshot_id
          WHERE transit_snapshots.fetched_at >= '#{range_start.utc.iso8601}'
          GROUP BY journey_id
        ) lasts ON vehicle_positions.journey_id = lasts.journey_id AND vehicle_positions.transit_snapshot_id = lasts.last_snap")
        .group(Arel.sql("EXTRACT(HOUR FROM transit_snapshots.fetched_at)::int"))
        .order(Arel.sql("EXTRACT(HOUR FROM transit_snapshots.fetched_at)::int"))
        .count
        .transform_keys { |h| "#{h.to_s.rjust(2, '0')}:00" }

      # By category
      @by_category = @terminated.group_by(&:category)
    else
      @terminated = []
      @active = []
      @hotspots = []
      @by_hour = {}
      @by_category = {}
    end
  end

  def line_delays
    @line = params[:line]
    range_start = 24.hours.ago

    # Line info from latest snapshot
    @line_info = LineHealthSummary.current.find_by(line: @line)
    return redirect_to(delays_path, alert: "Line not found") unless @line_info

    # Get real stop order from live vehicle data
    @stop_order = ordered_stops_for_line(@line)

    # Station delay accumulation — which stops are the bottlenecks?
    @station_delays_1d = station_delay_profile(@line, 24.hours.ago, @stop_order)
    @station_delays_7d = station_delay_profile(@line, 7.days.ago, @stop_order)

    # Delay trend for this line
    @delay_trend = LineHealthSummary.for_line(@line)
      .in_range(range_start, Time.current)
      .group_by_period(:minute, :recorded_at, n: 5)
      .maximum(:max_delay_seconds)
      .transform_values { |v| ((v || 0) / 60.0).round(1) }

    @avg_trend = LineHealthSummary.for_line(@line)
      .in_range(range_start, Time.current)
      .group_by_period(:minute, :recorded_at, n: 5)
      .average(:avg_delay_seconds)
      .transform_values { |v| ((v || 0) / 60.0).round(1) }

    # Current vehicles on this line from latest snapshot
    latest_snapshot = TransitSnapshot.latest
    @current_vehicles = if latest_snapshot
      VehiclePosition
        .where(transit_snapshot: latest_snapshot, line: @line)
        .order(:direction, :lat)
    else
      VehiclePosition.none
    end

    # Reliability for this line
    total = LineHealthSummary.for_line(@line).in_range(range_start, Time.current).count
    ok = LineHealthSummary.for_line(@line).in_range(range_start, Time.current).where(status: "ok").count
    @reliability = total > 0 ? (ok.to_f / total * 100).round(1) : 100

    # When do delays happen? Avg delay by hour of day for this line
    @delay_by_hour = VehiclePosition
      .joins(:transit_snapshot)
      .where(line: @line)
      .where(transit_snapshots: { fetched_at: range_start.. })
      .where("vehicle_positions.delay_seconds > 0")
      .group(Arel.sql("EXTRACT(HOUR FROM transit_snapshots.fetched_at)::int"))
      .average(:delay_seconds)
      .sort_by(&:first)
      .to_h { |hour, avg| ["#{hour.to_i.to_s.rjust(2, '0')}:00", ((avg || 0) / 60.0).round(1)] }
  end

  def delays
    @current_health = LineHealthSummary.current.order(:category, :line)
    @latest_at = LineHealthSummary.latest_timestamp

    # Stats for the last 24 hours
    range_start = 24.hours.ago
    @all_summaries = LineHealthSummary.in_range(range_start, Time.current)

    # Delay distribution over time (for the area chart)
    @delay_over_time = @all_summaries
      .group_by_period(:minute, :recorded_at, n: 5)
      .average(:avg_delay_seconds)
      .transform_values { |v| ((v || 0) / 60.0).round(1) }

    # Reliability score: % of snapshots where status was "ok" per line
    total_by_line = @all_summaries.group(:line).count
    ok_by_line = @all_summaries.where(status: "ok").group(:line).count
    @reliability = total_by_line
      .map { |line, total|
        ok = ok_by_line[line] || 0
        score = total > 0 ? (ok.to_f / total * 100).round(1) : 0
        category_row = @all_summaries.where(line: line).pick(:category, :category_color)
        [line, score, category_row&.first, category_row&.last]
      }
      .sort_by { |_, score, _, _| score }
  end

  private

  def station_delay_profile(line, since, stop_order)
    records = StopDelayRecord
      .joins(:transit_snapshot)
      .where(line: line)
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

    # Use the live-derived stop order; fall back to alphabetical for unknown stops
    all_ordered = stop_order.values.flatten
    stop_stats.sort_by do |name, _, _, _, _|
      idx = all_ordered.index(name)
      idx || (all_ordered.size + name.to_s.ord)
    end
  end

  def ordered_stops_for_line(line)
    snapshot = TransitSnapshot.latest
    return {} unless snapshot

    # Get stop sequences per vehicle from the latest snapshot
    records = StopDelayRecord
      .where(transit_snapshot: snapshot, line: line)
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

  # Topological sort to merge overlapping stop sequences into one ordered list
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

    # Kahn's algorithm
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

    # Append any stops caught in cycles
    result + (all_stops - result)
  end
end
