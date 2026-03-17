module Api
  class StopDelaysController < ApplicationController
    skip_before_action :authenticate_user!

    # GET /api/stop_delays?city=wien&line=13A
    # Returns per-stop delay stats for a line
    def index
      city = params[:city] || "wien"
      line = params[:line]
      return render(json: { error: "line parameter required" }, status: :bad_request) unless line.present?

      since = params[:since].present? ? Time.parse(params[:since]) : 24.hours.ago

      stops = StopDelayRecord
        .joins(:transit_snapshot)
        .where(city: city, line: line)
        .where(transit_snapshots: { fetched_at: since.. })
        .group(:stop_name)
        .pluck(
          :stop_name,
          Arel.sql("ROUND(AVG(stop_delay_records.delay_seconds)) as avg_delay"),
          Arel.sql("SUM(stop_delay_records.delay_seconds) as total_delay"),
          Arel.sql("MAX(stop_delay_records.delay_seconds) as peak_delay"),
          Arel.sql("COUNT(*) as occurrences")
        )
        .map { |name, avg, total, peak, count|
          { stop: name, avg_delay_seconds: avg.to_i, total_delay_seconds: total.to_i,
            peak_delay_seconds: peak.to_i, occurrences: count }
        }
        .sort_by { |s| -s[:total_delay_seconds] }

      render json: { city: city, line: line, since: since.iso8601, stops: stops }
    rescue ArgumentError
      render json: { error: "invalid date format" }, status: :bad_request
    end
  end
end
