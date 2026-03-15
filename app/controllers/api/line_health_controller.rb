module Api
  class LineHealthController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      scope = LineHealthSummary.current
      scope = scope.where(category: params[:category]) if params[:category].present?

      lines = scope.order(:category, :line)
      summary = {
        total_lines: lines.size,
        ok: lines.count { |l| l.status == "ok" },
        minor_delay: lines.count { |l| l.status == "minor_delay" },
        major_delay: lines.count { |l| l.status == "major_delay" },
        disrupted: lines.count { |l| l.status == "disrupted" }
      }

      render json: {
        lines: lines.map { |l| line_json(l) },
        summary: summary,
        recorded_at: lines.first&.recorded_at&.iso8601
      }
    end

    def history
      line = params[:line]
      return render(json: { error: "line parameter required" }, status: :bad_request) unless line.present?

      from = params[:from].present? ? Time.parse(params[:from]) : 1.hour.ago
      to = params[:to].present? ? Time.parse(params[:to]) : Time.current

      records = LineHealthSummary.for_line(line).in_range(from, to).order(:recorded_at)

      render json: {
        line: line,
        category: records.first&.category,
        data_points: records.map { |r|
          {
            recorded_at: r.recorded_at.iso8601,
            avg_delay_seconds: r.avg_delay_seconds,
            max_delay_seconds: r.max_delay_seconds,
            vehicle_count: r.vehicle_count,
            stalled_count: r.stalled_count,
            status: r.status
          }
        }
      }
    rescue ArgumentError
      render json: { error: "invalid date format" }, status: :bad_request
    end

    private

    def line_json(line)
      {
        line: line.line,
        category: line.category,
        category_color: line.category_color,
        vehicle_count: line.vehicle_count,
        avg_delay_seconds: line.avg_delay_seconds,
        max_delay_seconds: line.max_delay_seconds,
        stalled_count: line.stalled_count,
        status: line.status,
        recorded_at: line.recorded_at.iso8601
      }
    end
  end
end
