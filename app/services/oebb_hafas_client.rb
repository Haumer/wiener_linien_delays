require "json"
require "net/http"

class OebbHafasClient
  class Error < StandardError; end

  ENDPOINT = URI("https://fahrplan.oebb.at/gate").freeze
  REQUEST_ID = "2hg4aqaekeqmww4s".freeze
  VERSION = "1.88".freeze
  EXTENSION = "OEBB.14".freeze
  AUTH = { type: "AID", aid: "5vHavmuWPWIfetEe" }.freeze
  CLIENT = {
    id: "OEBB",
    type: "WEB",
    name: "webapp",
    l: "vs_webapp",
    v: 21_901
  }.freeze

  def call(method_name, request_payload)
    uri = ENDPOINT.dup
    uri.query = URI.encode_www_form(rnd: current_request_id)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = JSON.generate(payload(method_name, request_payload))
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "OEBB live feed returned HTTP #{response.code}"
    end

    body = JSON.parse(response.body)
    validate_response!(body, method_name)
  rescue JSON::ParserError => e
    raise Error, "OEBB live feed returned invalid JSON: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
    raise Error, "OEBB live feed is unreachable: #{e.message}"
  end

  private

  def payload(method_name, request_payload)
    {
      id: REQUEST_ID,
      ver: VERSION,
      lang: "deu",
      auth: AUTH,
      client: CLIENT,
      ext: EXTENSION,
      formatted: false,
      svcReqL: [
        {
          meth: method_name,
          req: request_payload
        }
      ]
    }
  end

  def validate_response!(body, method_name)
    unless body["err"] == "OK"
      raise Error, "OEBB live feed error for #{method_name}: #{body['err'] || 'unknown'}"
    end

    service_response = Array(body["svcResL"]).first

    unless service_response&.dig("err") == "OK"
      raise Error, "OEBB live feed service error for #{method_name}: #{service_response&.dig('err') || 'unknown'}"
    end

    service_response.fetch("res")
  rescue KeyError => e
    raise Error, "OEBB live feed response is missing data: #{e.message}"
  end

  def current_request_id
    (Time.current.to_f * 1000).to_i
  end
end
