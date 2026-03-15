class StopOverlayService
  LIVE_MATCH_DISTANCE_METERS = 140

  def initialize(
    cache: Gtfs::StopCache.new,
    source_manager: Gtfs::SourceManager.new,
    live_service: OebbStopService.new
  )
    @cache = cache
    @source_manager = source_manager
    @live_service = live_service
  end

  def call(rect: nil)
    payload = if @cache.available?
      @cache.read
    elsif @source_manager.ready_for_compile?
      rebuild!
    else
      return @live_service.call(rect: rect)
    end

    stops = filter_stops(Array(payload[:stops]), rect)
    live_stops = fetch_live_stops(rect)

    {
      available: payload[:available] != false,
      generated_at: payload[:generated_at],
      meta: payload[:meta],
      stops: merge_live_metadata(stops, live_stops),
      count: stops.size
    }
  rescue StandardError => e
    fallback_payload = @live_service.call(rect: rect)
    fallback_payload.merge(error: e.message)
  end

  def rebuild!(force: false)
    @source_manager.refresh!(force: force)
    payload = Gtfs::ViennaStopCompiler.new(sources: @source_manager.ready_sources).call
    @cache.write!(payload)
  end

  private

  def filter_stops(stops, rect)
    return stops unless rect

    min_lat = rect.dig(:llCrd, :y).to_f / 1_000_000
    min_lng = rect.dig(:llCrd, :x).to_f / 1_000_000
    max_lat = rect.dig(:urCrd, :y).to_f / 1_000_000
    max_lng = rect.dig(:urCrd, :x).to_f / 1_000_000

    stops.select do |stop|
      stop[:lat].to_f.between?(min_lat, max_lat) && stop[:lng].to_f.between?(min_lng, max_lng)
    end
  end

  def fetch_live_stops(rect)
    @live_service.call(rect: rect).fetch(:stops, [])
  rescue StandardError
    []
  end

  def merge_live_metadata(stops, live_stops)
    live_stops_by_name = live_stops.group_by { |stop| normalized_name(stop[:name]) }

    stops.map do |stop|
      candidates = live_stops_by_name.fetch(normalized_name(stop[:name]), [])
      live_stop = nearest_live_stop(stop, candidates)
      next stop unless live_stop

      stop.merge(
        lid: live_stop[:lid],
        live_departures_available: live_stop[:lid].present?
      )
    end
  end

  def nearest_live_stop(stop, candidates)
    candidates
      .map { |candidate| [distance_meters(stop, candidate), candidate] }
      .select { |distance, _candidate| distance <= LIVE_MATCH_DISTANCE_METERS }
      .min_by(&:first)
      &.last
  end

  def distance_meters(a, b)
    lat1 = a[:lat].to_f * Math::PI / 180
    lat2 = b[:lat].to_f * Math::PI / 180
    dlat = lat2 - lat1
    dlng = (b[:lng].to_f - a[:lng].to_f) * Math::PI / 180
    mean_lat = (lat1 + lat2) / 2.0
    x = dlng * Math.cos(mean_lat)
    y = dlat

    Math.sqrt((x * 6_371_000)**2 + (y * 6_371_000)**2)
  end

  def normalized_name(value)
    value.to_s.downcase.gsub(/\s+/, " ").strip
  end
end
