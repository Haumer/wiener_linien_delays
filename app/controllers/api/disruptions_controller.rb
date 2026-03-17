module Api
  class DisruptionsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      city = params[:city] || "wien"
      disrupted = LineHealthSummary.current_for(city)
        .where(status: %w[major_delay disrupted])
        .order(max_delay_seconds: :desc)

      render json: {
        city: city,
        disruptions: disrupted.map { |l|
          {
            line: l.line,
            category: l.category,
            category_color: l.category_color,
            avg_delay_seconds: l.avg_delay_seconds,
            max_delay_seconds: l.max_delay_seconds,
            stalled_count: l.stalled_count,
            vehicle_count: l.vehicle_count,
            status: l.status,
            recorded_at: l.recorded_at.iso8601
          }
        },
        count: disrupted.size
      }
    end
  end
end
