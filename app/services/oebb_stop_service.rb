class OebbStopService
  include OebbTransitSupport

  VIENNA_RECT = OebbVehicleService::VIENNA_RECT

  def initialize(client: OebbHafasClient.new)
    @client = client
  end

  def call(rect: nil)
    stops = Rails.cache.fetch(cache_key(rect), expires_in: 5.minutes) do
      response = @client.call(
        "LocGeoPos",
        {
          getStops: true,
          getPOIs: false,
          maxLoc: 5000,
          rect: rect || VIENNA_RECT
        }
      )

      extract_stops(response)
    end

    {
      stops: stops,
      count: stops.size
    }
  end

  private

  def cache_key(rect)
    return "oebb/stops/v4/default" unless rect

    "oebb/stops/v4/#{rect.dig(:llCrd, :x)}-#{rect.dig(:llCrd, :y)}-#{rect.dig(:urCrd, :x)}-#{rect.dig(:urCrd, :y)}"
  end

  def extract_stops(response)
    products = Array(response.dig("common", "prodL"))

    Array(response.dig("common", "locL")).filter_map do |location|
      category_keys = Array(location["pRefL"]).filter_map do |product_index|
        normalize_product(products[product_index])
      end.map { |category| category[:key] }

      category_keys |= stop_categories_from_class(location["pCls"])
      next if category_keys.empty?
      next unless location.dig("crd", "x") && location.dig("crd", "y")

      primary_category = pick_primary_category(category_keys)

      {
        id: location["extId"],
        name: location["name"],
        lid: location["lid"],
        lat: location.dig("crd", "y").to_f / 1_000_000,
        lng: location.dig("crd", "x").to_f / 1_000_000,
        primary_category: primary_category,
        category_label: CATEGORY_CONFIG.fetch(primary_category)[:label],
        category_color: CATEGORY_CONFIG.fetch(primary_category)[:color],
        categories: category_keys.map do |key|
          CATEGORY_CONFIG.fetch(key).merge(key:)
        end
      }
    end
  end
end
