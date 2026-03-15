require "csv"
require "set"

module Gtfs
  class ViennaLineCompiler
    SIMPLIFICATION_TOLERANCE = 0.00008

    def initialize(sources:, bounds: SourceCatalog::VIENNA_BOUNDS)
      @sources = sources
      @bounds = bounds
    end

    def call
      features = @sources.flat_map { |source| compile_source(source) }

      {
        type: "FeatureCollection",
        available: true,
        generated_at: Time.current.iso8601,
        meta: {
          line_count: features.size,
          sources: @sources.map { |source| source.fetch(:label) }
        },
        features: features.sort_by do |feature|
          [
            feature.dig(:properties, :category).to_s,
            feature.dig(:properties, :line).to_s,
            feature.dig(:properties, :source).to_s
          ]
        end
      }
    end

    private

    def compile_source(source)
      extract_dir = source.fetch(:extract_dir)
      scoped_stop_ids = stop_ids_within_bounds(extract_dir.join("stops.txt"))
      return [] if scoped_stop_ids.empty?

      scoped_trip_ids = trip_ids_for_stop_ids(extract_dir.join("stop_times.txt"), scoped_stop_ids)
      return [] if scoped_trip_ids.empty?

      trip_shapes, route_ids = shape_metadata(extract_dir.join("trips.txt"), scoped_trip_ids)
      return [] if trip_shapes.empty?

      route_lookup = route_metadata(extract_dir.join("routes.txt"), route_ids, source)
      relevant_shapes = trip_shapes.select { |_shape_id, trip| route_lookup.key?(trip[:route_id]) }
      return [] if relevant_shapes.empty?

      shape_points = shapes_for_ids(extract_dir.join("shapes.txt"), relevant_shapes.keys.to_set)

      relevant_shapes.filter_map do |shape_id, trip|
        route = route_lookup[trip[:route_id]]
        points = simplify_points(compact_points(shape_points.fetch(shape_id, [])))
        next if points.length < 2

        {
          type: "Feature",
          properties: {
            id: "#{source.fetch(:key)}:#{trip[:route_id]}:#{shape_id}",
            source: source.fetch(:label),
            route_id: trip[:route_id],
            shape_id: shape_id,
            line: route[:line],
            line_token: normalized_line_token(route[:line]),
            name: route[:name],
            headsign: trip[:headsign],
            category: route[:category],
            category_label: route[:category_label],
            category_color: route[:category_color]
          },
          geometry: {
            type: "LineString",
            coordinates: points.map { |lat, lng| [lng.round(6), lat.round(6)] }
          }
        }
      end
    end

    def stop_ids_within_bounds(stops_path)
      scoped_stop_ids = Set.new

      each_csv_row(stops_path) do |row|
        lat = row["stop_lat"].to_f
        lng = row["stop_lon"].to_f
        next unless within_bounds?(lat, lng)

        scoped_stop_ids << row["stop_id"]
      end

      scoped_stop_ids
    end

    def trip_ids_for_stop_ids(stop_times_path, stop_ids)
      scoped_trip_ids = Set.new

      each_csv_row(stop_times_path) do |row|
        scoped_trip_ids << row["trip_id"] if stop_ids.include?(row["stop_id"])
      end

      scoped_trip_ids
    end

    def shape_metadata(trips_path, trip_ids)
      shapes = {}
      route_ids = Set.new

      each_csv_row(trips_path) do |row|
        next unless trip_ids.include?(row["trip_id"])

        shape_id = row["shape_id"].to_s.strip
        route_id = row["route_id"].to_s.strip
        next if shape_id.blank? || route_id.blank?

        route_ids << route_id
        shapes[shape_id] ||= {
          route_id: route_id,
          headsign: row["trip_headsign"].to_s.strip.presence
        }
      end

      [shapes, route_ids]
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

    def shapes_for_ids(shapes_path, shape_ids)
      grouped = Hash.new { |hash, key| hash[key] = [] }

      each_csv_row(shapes_path) do |row|
        shape_id = row["shape_id"].to_s.strip
        next unless shape_ids.include?(shape_id)

        grouped[shape_id] << [
          row["shape_pt_sequence"].to_i,
          row["shape_pt_lat"].to_f,
          row["shape_pt_lon"].to_f
        ]
      end

      grouped.transform_values do |points|
        points
          .sort_by(&:first)
          .map { |_sequence, lat, lng| [lat, lng] }
      end
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

      details = OebbTransitSupport::CATEGORY_CONFIG.fetch(category)
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

    def within_bounds?(lat, lng)
      lat.between?(@bounds.fetch(:min_lat), @bounds.fetch(:max_lat)) &&
        lng.between?(@bounds.fetch(:min_lng), @bounds.fetch(:max_lng))
    end

    def each_csv_row(path, &block)
      CSV.foreach(path, headers: true, encoding: "bom|utf-8", &block)
    end

    def compact_points(points)
      points.each_with_object([]) do |point, compacted|
        compacted << point if compacted.last != point
      end
    end

    def simplify_points(points)
      return points if points.length < 3

      kept_indexes = Set.new([0, points.length - 1])
      simplify_segment(points, 0, points.length - 1, SIMPLIFICATION_TOLERANCE**2, kept_indexes)

      kept_indexes.to_a.sort.map { |index| points[index] }
    end

    def simplify_segment(points, first_index, last_index, tolerance_squared, kept_indexes)
      max_distance_squared = 0.0
      split_index = nil
      first = points[first_index]
      last = points[last_index]

      ((first_index + 1)...last_index).each do |index|
        distance_squared = perpendicular_distance_squared(points[index], first, last)
        next unless distance_squared > max_distance_squared

        max_distance_squared = distance_squared
        split_index = index
      end

      return unless split_index && max_distance_squared > tolerance_squared

      kept_indexes << split_index
      simplify_segment(points, first_index, split_index, tolerance_squared, kept_indexes)
      simplify_segment(points, split_index, last_index, tolerance_squared, kept_indexes)
    end

    def perpendicular_distance_squared(point, start_point, end_point)
      x0 = point.last
      y0 = point.first
      x1 = start_point.last
      y1 = start_point.first
      x2 = end_point.last
      y2 = end_point.first

      dx = x2 - x1
      dy = y2 - y1

      return (x0 - x1)**2 + (y0 - y1)**2 if dx.zero? && dy.zero?

      projection = ((x0 - x1) * dx + (y0 - y1) * dy) / (dx**2 + dy**2)
      projection = projection.clamp(0.0, 1.0)
      x = x1 + projection * dx
      y = y1 + projection * dy

      (x0 - x)**2 + (y0 - y)**2
    end

    def normalized_line_token(value)
      value.to_s.gsub(/\s+/, "").downcase
    end
  end
end
