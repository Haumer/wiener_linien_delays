module Api
  class VehiclesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      render json: OebbVehicleService.new.call
    rescue OebbHafasClient::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end
  end
end
