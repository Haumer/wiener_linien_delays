require "fileutils"
require "json"

module Gtfs
  class StopCache
    def initialize(path: SourceCatalog::STOPS_CACHE_PATH)
      @path = path
    end

    def available?
      @path.exist?
    end

    def read
      return unavailable_payload unless available?

      JSON.parse(@path.read, symbolize_names: true)
    rescue JSON::ParserError
      unavailable_payload("The stop cache is unreadable. Rebuild it with `bin/rake transit:refresh_stops`.")
    end

    def write!(payload)
      FileUtils.mkdir_p(@path.dirname)
      File.write(@path, JSON.pretty_generate(payload))
      payload
    end

    def unavailable_payload(message = "Stop overlay is not built yet. Run `bin/rake transit:refresh_stops`.")
      {
        available: false,
        generated_at: nil,
        meta: {
          stop_count: 0,
          sources: []
        },
        error: message,
        stops: []
      }
    end
  end
end
