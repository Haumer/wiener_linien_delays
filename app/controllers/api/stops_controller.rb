module Api
  class StopsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      render json: StopOverlayService.new.call(rect: stop_rect)
    rescue OebbHafasClient::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    def departures
      if params[:lid].blank?
        render json: { error: "Stop lid is required" }, status: :bad_request
        return
      end

      render json: OebbStopBoardService.new.call(lid: params[:lid], name: params[:name])
    rescue OebbHafasClient::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    private

    def stop_rect
      return unless rect_params.values.all?(&:present?)

      {
        llCrd: {
          x: (rect_params[:sw_lng].to_f * 1_000_000).round,
          y: (rect_params[:sw_lat].to_f * 1_000_000).round
        },
        urCrd: {
          x: (rect_params[:ne_lng].to_f * 1_000_000).round,
          y: (rect_params[:ne_lat].to_f * 1_000_000).round
        }
      }
    end

    def rect_params
      params.permit(:sw_lat, :sw_lng, :ne_lat, :ne_lng)
    end
  end
end
