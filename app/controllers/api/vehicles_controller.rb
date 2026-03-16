module Api
  class VehiclesController < ApplicationController
    include OebbTransitSupport

    skip_before_action :authenticate_user!

    def index
      snapshot = TransitSnapshot.latest

      unless snapshot
        render json: { vehicles: [], counts: category_counts([]), fetched_at: nil }
        return
      end

      positions = VehiclePosition.where(transit_snapshot: snapshot)

      # Load next stops per vehicle from stop_delay_records
      stops_by_vehicle = StopDelayRecord
        .where(transit_snapshot: snapshot)
        .where.not(journey_id: [nil, ""])
        .order(:stop_sequence)
        .group_by(&:journey_id)

      vehicles = positions.map do |vp|
        config = CATEGORY_CONFIG[vp.category] || { label: vp.category, color: "#94a3b8" }
        stop_records = stops_by_vehicle[vp.journey_id] || []

        {
          id: vp.journey_id,
          name: vp.line,
          line: vp.line,
          category: vp.category,
          category_label: config[:label],
          category_color: config[:color],
          lat: vp.lat.to_f,
          lng: vp.lng.to_f,
          direction: vp.direction,
          progress: nil,
          next_stops: stop_records.map do |sr|
            {
              name: sr.stop_name,
              minutes_away: (sr.delay_seconds / 60.0).ceil,
              realtime_at: nil,
              scheduled_at: nil
            }
          end
        }
      end

      counts = CATEGORY_CONFIG.keys.index_with do |key|
        vehicles.count { |v| v[:category] == key }
      end

      render json: {
        vehicles: vehicles,
        counts: counts,
        fetched_at: snapshot.fetched_at.iso8601
      }
    end
  end
end
