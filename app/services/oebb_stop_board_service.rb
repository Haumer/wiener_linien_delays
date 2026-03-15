class OebbStopBoardService
  include OebbTransitSupport

  def initialize(client: OebbHafasClient.new)
    @client = client
  end

  def call(lid:, name: nil)
    response = @client.call(
      "StationBoard",
      {
        type: "DEP",
        sort: "PT",
        maxJny: 8,
        stbLoc: {
          name: name.presence || "Stop",
          lid: lid
        }
      }
    )

    departures = extract_departures(response)
    {
      stop: {
        name: Array(response.dig("common", "locL")).first&.dig("name") || name,
        lid: lid
      },
      departures: departures,
      fetched_at: parse_service_time(response["sD"], response["sT"])&.iso8601
    }
  end

  private

  def extract_departures(response)
    products = Array(response.dig("common", "prodL"))
    board_time = parse_service_time(response["sD"], response["sT"]) || Time.current.in_time_zone(OebbTransitSupport::VIENNA_TIME_ZONE)

    Array(response["jnyL"]).filter_map do |journey|
      stop_data = journey["stbStop"] || {}
      product_index = stop_data["dProdX"] || journey.dig("prodL", 0, "prodX") || journey["prodX"]
      product = products[product_index]
      category = normalize_product(product)

      next unless category

      realtime_at = parse_service_time(journey["date"], stop_data["dTimeR"] || stop_data["aTimeR"])
      scheduled_at = parse_service_time(journey["date"], stop_data["dTimeS"] || stop_data["aTimeS"])
      departure_time = realtime_at || scheduled_at

      next unless departure_time

      {
        line: product&.dig("prodCtx", "line").to_s.presence || product&.fetch("name", "").to_s.strip,
        name: product&.fetch("name", "").to_s.strip,
        category: category[:key],
        category_label: category[:label],
        category_color: category[:color],
        destination: journey["dirTxt"],
        scheduled_at: scheduled_at&.iso8601,
        realtime_at: realtime_at&.iso8601,
        minutes_away: round_minutes_between(board_time, departure_time),
        platform: stop_data.dig("dPltfS", "txt") || stop_data.dig("aPltfS", "txt")
      }
    end
  end
end
