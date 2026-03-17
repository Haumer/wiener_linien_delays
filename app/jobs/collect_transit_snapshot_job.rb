class CollectTransitSnapshotJob < ApplicationJob
  include OebbTransitSupport

  queue_as :default

  STALL_THRESHOLD_DEGREES = 0.00005

  def perform
    CityConfig.enabled.each do |city_key|
      collect_city(city_key)
    rescue OebbHafasClient::Error => e
      Rails.logger.warn("Transit snapshot failed for #{city_key}: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("Unexpected error collecting #{city_key}: #{e.message}")
    end
  end

  private

  def collect_city(city_key)
    config = CityConfig.find(city_key)
    return unless config

    data = OebbVehicleService.new(rect: config[:rect]).call
    vehicles = data[:vehicles] || []
    fetched_at = data[:fetched_at] ? Time.parse(data[:fetched_at]) : Time.current

    snapshot = TransitSnapshot.create!(
      city: city_key,
      fetched_at: fetched_at,
      vehicle_count: vehicles.size
    )

    previous_positions = load_previous_positions(city_key)
    line_buckets = Hash.new { |h, k| h[k] = { delays: [], stalled: 0, vehicles: 0, category: nil, color: nil } }

    records = vehicles.map do |vehicle|
      delay = compute_delay(vehicle)
      stalled = stalled?(vehicle, previous_positions[vehicle[:id]])

      line = vehicle[:line].presence || vehicle[:name]
      bucket = line_buckets[line]
      bucket[:delays] << (delay || 0)
      bucket[:stalled] += 1 if stalled
      bucket[:vehicles] += 1
      bucket[:category] ||= vehicle[:category]
      bucket[:color] ||= vehicle[:category_color]

      {
        transit_snapshot_id: snapshot.id,
        city: city_key,
        journey_id: vehicle[:id],
        line: line,
        category: vehicle[:category],
        direction: vehicle[:direction],
        lat: vehicle[:lat],
        lng: vehicle[:lng],
        delay_seconds: delay,
        stalled: stalled,
        next_stop_name: vehicle[:next_stops]&.first&.dig(:name)
      }
    end

    VehiclePosition.insert_all(records) if records.any?
    record_stop_delays(snapshot, city_key, vehicles)
    record_line_health(city_key, line_buckets, fetched_at)
  end

  def compute_delay(vehicle)
    stop = (vehicle[:next_stops] || []).find { |s| s[:realtime_at] && s[:scheduled_at] }
    return unless stop

    realtime = Time.parse(stop[:realtime_at])
    scheduled = Time.parse(stop[:scheduled_at])
    delay = (realtime - scheduled).to_i
    [delay, 0].max
  rescue ArgumentError
    nil
  end

  def stalled?(vehicle, previous)
    return false unless previous

    (vehicle[:lat] - previous[:lat]).abs < STALL_THRESHOLD_DEGREES &&
      (vehicle[:lng] - previous[:lng]).abs < STALL_THRESHOLD_DEGREES
  end

  def load_previous_positions(city_key)
    last_snapshot = TransitSnapshot.where(city: city_key).order(fetched_at: :desc).first
    return {} unless last_snapshot

    VehiclePosition
      .where(transit_snapshot: last_snapshot)
      .pluck(:journey_id, :lat, :lng)
      .to_h { |jid, lat, lng| [jid, { lat: lat.to_f, lng: lng.to_f }] }
  end

  def record_stop_delays(snapshot, city_key, vehicles)
    records = []

    vehicles.each do |vehicle|
      line = vehicle[:line].presence || vehicle[:name]
      (vehicle[:next_stops] || []).each_with_index do |stop, i|
        next unless stop[:name].present?

        delay = if stop[:realtime_at] && stop[:scheduled_at]
          [(Time.parse(stop[:realtime_at]) - Time.parse(stop[:scheduled_at])).to_i, 0].max
        else
          0
        end

        records << {
          transit_snapshot_id: snapshot.id,
          city: city_key,
          journey_id: vehicle[:id],
          line: line,
          category: vehicle[:category],
          direction: vehicle[:direction],
          stop_name: stop[:name],
          delay_seconds: delay,
          stop_sequence: i
        }
      end
    end

    StopDelayRecord.insert_all(records) if records.any?
  rescue ArgumentError
    # Bad time parsing — skip
  end

  def record_line_health(city_key, buckets, recorded_at)
    records = buckets.map do |line, data|
      delays = data[:delays]
      avg = delays.any? ? (delays.sum.to_f / delays.size).round : 0
      max = delays.max || 0

      status = if data[:stalled] > 0 && avg >= 300
        "disrupted"
      elsif avg >= 300
        "major_delay"
      elsif avg >= 180
        "minor_delay"
      else
        "ok"
      end

      {
        city: city_key,
        line: line,
        category: data[:category],
        category_color: data[:color] || "#94a3b8",
        recorded_at: recorded_at,
        vehicle_count: data[:vehicles],
        avg_delay_seconds: avg,
        max_delay_seconds: max,
        stalled_count: data[:stalled],
        status: status
      }
    end

    LineHealthSummary.insert_all(records) if records.any?
  end
end
