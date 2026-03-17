module Api
  class StubsController < ApplicationController
    skip_before_action :authenticate_user!

    def empty_array
      render json: { stops: [], departures: [] }
    end

    def empty_geojson
      render json: { type: "FeatureCollection", features: [], available: false }
    end
  end
end
