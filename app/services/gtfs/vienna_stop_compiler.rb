require "csv"
require "set"

module Gtfs
  class ViennaStopCompiler
    include OebbTransitSupport

    def initialize(sources:, bounds: SourceCatalog::VIENNA_BOUNDS)
      @sources = sources
      @bounds = bounds
    end

    def call
      stops = @sources.flat_map { |source| compile_source(source) }

      {
        available: true,
        generated_at: Time.current.iso8601,
        meta: {
          stop_count: stops.size,
          sources: @sources.map { |source| source.fetch(:label) }
        },
        stops: stops.sort_by do |stop|
          [
            stop.fetch(:name).to_s,
            stop.fetch(:primary_category).to_s,
            stop.fetch(:lat),
            stop.fetch(:lng)
          ]
        end
      }
    end

    private

    def compile_source(source)
      extract_dir = source.fetch(:extract_dir)
      stops_by_id = load_stops(extract_dir.join("stops.txt"))
      scoped_stops, stop_to_canonical = scoped_stops_for_source(stops_by_id, source)
      return [] if scoped_stops.empty?

      trip_ids_by_stop = trip_ids_for_stop_ids(extract_dir.join("stop_times.txt"), stop_to_canonical)
      return [] if trip_ids_by_stop.empty?

      trip_route_lookup = route_ids_for_trip_ids(extract_dir.join("trips.txt"), trip_ids_by_stop.values.reduce(Set.new, :|))
      route_lookup = route_metadata(extract_dir.join("routes.txt"), trip_route_lookup.values.to_set, source)

      scoped_stops.values.filter_map do |stop|
        route_ids = trip_ids_by_stop.fetch(stop[:canonical_id], Set.new).filter_map { |trip_id| trip_route_lookup[trip_id] }
        lines = route_ids.filter_map { |route_id| route_lookup[route_id] }
                         .uniq { |route| [route[:category], route[:line]] }
                         .sort_by { |route| [route[:category].to_s, route[:line].to_s] }
        next if lines.empty?

        categories = lines.map { |route| route[:category] }.uniq
        primary_category = pick_primary_category(categories)

        {
          id: "#{source.fetch(:key)}:#{stop[:canonical_id]}",
          source: source.fetch(:label),
          name: stop[:name],
          lat: stop[:lat].round(6),
          lng: stop[:lng].round(6),
          primary_category: primary_category,
          category_label: CATEGORY_CONFIG.fetch(primary_category).fetch(:label),
          category_color: CATEGORY_CONFIG.fetch(primary_category).fetch(:color),
          categories: categories.map { |key| CATEGORY_CONFIG.fetch(key).merge(key:) },
          lines: lines.map do |route|
            {
              line: route[:line],
              category: route[:category],
              category_label: route[:category_label],
              category_color: route[:category_color]
            }
          end
        }
      end
    end

    def load_stops(path)
      stops_by_id = {}

      each_csv_row(path) do |row|
        stop_id = row["stop_id"].to_s.strip
        next if stop_id.blank?

        stops_by_id[stop_id] = row
      end

      stops_by_id
    end

    def scoped_stops_for_source(stops_by_id, source)
      scoped_stops = {}
      stop_to_canonical = {}

      stops_by_id.each_value do |row|
        stop_id = row["stop_id"].to_s.strip
        next if stop_id.blank?

        canonical_id = canonical_stop_id(row, stops_by_id)
        canonical_row = stops_by_id[canonical_id] || row
        lat = canonical_row["stop_lat"].to_f
        lng = canonical_row["stop_lon"].to_f
        next unless within_bounds?(lat, lng)

        stop_to_canonical[stop_id] = canonical_id
        scoped_stops[canonical_id] ||= {
          canonical_id: canonical_id,
          source: source.fetch(:label),
          name: canonical_name(canonical_row, row),
          lat: lat,
          lng: lng
        }
      end

      [scoped_stops, stop_to_canonical]
    end

    def trip_ids_for_stop_ids(stop_times_path, stop_to_canonical)
      trip_ids_by_stop = Hash.new { |hash, key| hash[key] = Set.new }

      each_csv_row(stop_times_path) do |row|
        stop_id = row["stop_id"].to_s.strip
        canonical_id = stop_to_canonical[stop_id]
        next unless canonical_id

        trip_id = row["trip_id"].to_s.strip
        next if trip_id.blank?

        trip_ids_by_stop[canonical_id] << trip_id
      end

      trip_ids_by_stop
    end

    def route_ids_for_trip_ids(trips_path, trip_ids)
      trip_route_lookup = {}

      each_csv_row(trips_path) do |row|
        trip_id = row["trip_id"].to_s.strip
        next unless trip_ids.include?(trip_id)

        route_id = row["route_id"].to_s.strip
        next if route_id.blank?

        trip_route_lookup[trip_id] = route_id
      end

      trip_route_lookup
    end

    def route_metadata(routes_path, route_ids, source)
      lookup = {}

      each_csv_row(routes_path) do |row|
        route_id = row["route_id"].to_s.strip
        next unless route_ids.include?(route_id)

        metadata = case source.fetch(:key).to_sym
        when :wiener_linien
          wiener_linien_route(row)
        when :oebb
          oebb_route(row)
        end

        next unless metadata

        lookup[route_id] = metadata
      end

      lookup
    end

    def wiener_linien_route(row)
      route_type = row["route_type"].to_i
      line = preferred_route_name(row)
      return if line.blank?
      return if line.match?(/\AU/i) || route_type == 1

      category = case route_type
      when 0 then "tram"
      when 3 then "bus"
      else
        nil
      end

      category_metadata(category, line, row["route_long_name"])
    end

    def oebb_route(row)
      line = preferred_route_name(row)
      return if line.blank?

      route_type = row["route_type"].to_i
      long_name = row["route_long_name"].to_s.strip
      category = if line.match?(/\AS\s*\d+/i) || long_name.match?(/s-?bahn/i)
        "sbahn"
      elsif route_type == 3
        nil
      else
        "rail"
      end

      category_metadata(category, line, long_name)
    end

    def category_metadata(category, line, long_name)
      return unless category

      details = CATEGORY_CONFIG.fetch(category)
      {
        line: line,
        name: long_name.to_s.strip.presence || line,
        category: category,
        category_label: details.fetch(:label),
        category_color: details.fetch(:color)
      }
    end

    def preferred_route_name(row)
      row["route_short_name"].to_s.strip.presence || row["route_long_name"].to_s.strip
    end

    def canonical_stop_id(row, stops_by_id)
      parent_station = row["parent_station"].to_s.strip
      return parent_station if parent_station.present? && stops_by_id.key?(parent_station)

      row["stop_id"].to_s.strip
    end

    def canonical_name(canonical_row, fallback_row)
      canonical_row["stop_name"].to_s.strip.presence ||
        fallback_row["stop_name"].to_s.strip.presence ||
        fallback_row["stop_id"].to_s.strip
    end

    def within_bounds?(lat, lng)
      lat.between?(@bounds.fetch(:min_lat), @bounds.fetch(:max_lat)) &&
        lng.between?(@bounds.fetch(:min_lng), @bounds.fetch(:max_lng))
    end

    def each_csv_row(path, &block)
      CSV.foreach(path, headers: true, encoding: "bom|utf-8", &block)
    end
  end
end
