class OebbVehicleService
  include OebbTransitSupport

  VIENNA_RECT = {
    llCrd: { x: 16_180_000, y: 48_110_000 },
    urCrd: { x: 16_580_000, y: 48_330_000 }
  }.freeze

  def initialize(client: OebbHafasClient.new)
    @client = client
  end

  def call
    response = @client.call(
      "JourneyGeoPos",
      {
        maxJny: 1000,
        onlyRT: true,
        rect: VIENNA_RECT
      }
    )

    vehicles = extract_vehicles(response)
    {
      vehicles: vehicles,
      counts: category_counts(vehicles),
      fetched_at: parse_service_time(response["date"], response["time"])&.iso8601
    }
  end

  private

  def extract_vehicles(response)
    products = Array(response.dig("common", "prodL"))
    locations = Array(response.dig("common", "locL"))
    feed_time = parse_service_time(response["date"], response["time"]) || Time.current.in_time_zone(OebbTransitSupport::VIENNA_TIME_ZONE)

    Array(response["jnyL"]).filter_map do |journey|
      product = products[journey["prodX"]]
      category = normalize_product(product)
      position = journey["pos"]

      next unless category && position

      {
        id: journey["jid"],
        name: product["name"].to_s.strip,
        line: product.dig("prodCtx", "line").to_s.presence || product["name"].to_s.strip,
        category: category[:key],
        category_label: category[:label],
        category_color: category[:color],
        raw_category_code: category[:code],
        lat: position["y"].to_f / 1_000_000,
        lng: position["x"].to_f / 1_000_000,
        direction: journey["dirTxt"],
        progress: journey["proc"],
        next_stops: extract_next_stops(
          stop_list: Array(journey["stopL"]),
          locations: locations,
          service_date: journey["date"] || response["date"],
          feed_time: feed_time
        )
      }
    end
  end

  def extract_next_stops(stop_list:, locations:, service_date:, feed_time:)
    stop_list.filter_map do |stop|
      next unless stop["locX"].is_a?(Integer)

      location = locations[stop["locX"]]
      next unless location && location["name"].present?

      realtime_at = parse_service_time(service_date, stop["aTimeR"] || stop["dTimeR"])
      scheduled_at = parse_service_time(service_date, stop["aTimeS"] || stop["dTimeS"])
      stop_time = realtime_at || scheduled_at

      next unless stop_time
      next if stop_time < feed_time - 1.minute

      {
        name: location["name"],
        lat: location.dig("crd", "y").to_f / 1_000_000,
        lng: location.dig("crd", "x").to_f / 1_000_000,
        realtime_at: realtime_at&.iso8601,
        scheduled_at: scheduled_at&.iso8601,
        minutes_away: round_minutes_between(feed_time, stop_time)
      }
    end.first(4)
  end
end
