module Api
  class CitiesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      cities = CityConfig.all.map do |key, config|
        latest = LineHealthSummary.latest_timestamp_for(key)
        line_count = latest ? LineHealthSummary.current_for(key).count : 0

        {
          key: key,
          name: config[:name],
          population: config[:population],
          center: { lat: config[:center][0], lng: config[:center][1] },
          has_data: latest.present?,
          lines_monitored: line_count,
          last_updated: latest&.iso8601
        }
      end

      render json: { cities: cities }
    end
  end
end
