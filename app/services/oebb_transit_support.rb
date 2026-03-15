module OebbTransitSupport
  VIENNA_TIME_ZONE = ActiveSupport::TimeZone["Europe/Vienna"]
  CATEGORY_CONFIG = {
    "tram" => { label: "Tram", color: "#e53935" },
    "bus" => { label: "Bus", color: "#1e88e5" },
    "sbahn" => { label: "S-Bahn", color: "#43a047" },
    "obus" => { label: "O-Bus", color: "#8e24aa" },
    "rail" => { label: "Train", color: "#ff9800" }
  }.freeze
  RAIL_CODES = %w[rex r rjx rj ice ic ec en d cjx wb rail n rex1 rex2 rex3 rex7].freeze
  STOP_CLASS_FLAGS = {
    "tram" => 512,
    "bus" => 64,
    "sbahn" => 32
  }.freeze
  RAIL_STOP_CLASS_FLAGS = 1 | 4 | 8 | 16 | 4096

  private

  def normalize_product(product)
    return unless product

    code = product.dig("prodCtx", "catOutS").to_s.strip
    long_name = product.dig("prodCtx", "catOutL").to_s
    display_name = product["name"].to_s

    key = case code
    when "str" then "tram"
    when "Bus" then "bus"
    when "s" then "sbahn"
    when "obu" then "obus"
    else
      next_key_for_other_product(code:, long_name:, display_name:)
    end

    return unless key

    CATEGORY_CONFIG.fetch(key).merge(key:, code:)
  end

  def next_key_for_other_product(code:, long_name:, display_name:)
    return if code.casecmp("u").zero?
    return if long_name.match?(/u-bahn/i)
    return if display_name.match?(/\bU[1-6]\b/)
    return "rail" if rail_product?(code:, long_name:, display_name:)
  end

  def rail_product?(code:, long_name:, display_name:)
    normalized_code = code.downcase
    return true if RAIL_CODES.include?(normalized_code)
    return true if long_name.match?(/bahn|zug|rail|westbahn|intercity|railjet/i)
    display_name.match?(/\b(REX|RJX?|ICE|IC|EC|EN|CJX|WB)\b/i)
  end

  def parse_service_time(date_string, time_string)
    return unless date_string.present? && time_string.present?

    date = Date.strptime(date_string, "%Y%m%d")
    raw_hour = time_string[0, 2].to_i
    hour = raw_hour % 24
    day_offset = raw_hour / 24

    VIENNA_TIME_ZONE.local(
      date.year,
      date.month,
      date.day,
      hour,
      time_string[2, 2].to_i,
      time_string[4, 2].to_i
    ) + day_offset.days
  rescue ArgumentError
    nil
  end

  def round_minutes_between(from_time, to_time)
    return 0 unless from_time && to_time

    minutes = ((to_time - from_time) / 60.0).round
    [minutes, 0].max
  end

  def category_counts(items)
    CATEGORY_CONFIG.keys.index_with do |key|
      items.count { |item| item[:category] == key }
    end
  end

  def stop_categories_from_class(product_class)
    bitmask = product_class.to_i
    categories = STOP_CLASS_FLAGS.filter_map do |key, flag|
      key if (bitmask & flag).positive?
    end

    categories << "rail" if (bitmask & RAIL_STOP_CLASS_FLAGS).positive?
    categories.uniq
  end

  def pick_primary_category(category_keys)
    %w[rail sbahn tram obus bus].find { |key| category_keys.include?(key) } || category_keys.first
  end
end
