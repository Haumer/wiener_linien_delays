require "fileutils"
require "json"

module Gtfs
  class LineCache
    def initialize(path: SourceCatalog::CACHE_PATH)
      @path = path
    end

    def available?
      @path.exist?
    end

    def read
      return unavailable_payload unless available?

      JSON.parse(@path.read, symbolize_names: true)
    rescue JSON::ParserError
      unavailable_payload("The line cache is unreadable. Rebuild it with `bin/rake transit:refresh_lines`.")
    end

    def write!(payload)
      FileUtils.mkdir_p(@path.dirname)
      File.write(@path, JSON.pretty_generate(payload))
      payload
    end

    def unavailable_payload(message = "Line overlay is not built yet. Run `bin/rake transit:refresh_lines`.")
      {
        type: "FeatureCollection",
        available: false,
        generated_at: nil,
        meta: {
          line_count: 0,
          sources: []
        },
        error: message,
        features: []
      }
    end
  end
end
