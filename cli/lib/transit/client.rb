require "net/http"
require "json"
require "uri"

module Transit
  class Client
    DEFAULT_HOST = ENV.fetch("TRANSIT_API_HOST", "http://localhost:3003")

    def initialize(host: DEFAULT_HOST)
      @host = host
    end

    def cities
      get("/api/cities")["cities"]
    end

    def line_health(city:, category: nil)
      params = { city: city }
      params[:category] = category if category
      get("/api/line_health", params)
    end

    def disruptions(city:)
      get("/api/disruptions", city: city)
    end

    def line_history(city:, line:, from: nil, to: nil)
      params = { city: city, line: line }
      params[:from] = from if from
      params[:to] = to if to
      get("/api/line_health/history", params)
    end

    private

    def get(path, params = {})
      uri = URI("#{@host}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      response = Net::HTTP.get_response(uri)
      JSON.parse(response.body)
    rescue Errno::ECONNREFUSED
      { "error" => "Cannot connect to #{@host}. Is the server running?" }
    rescue JSON::ParserError
      { "error" => "Invalid response from server" }
    end
  end
end
