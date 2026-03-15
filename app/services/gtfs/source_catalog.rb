module Gtfs
  module SourceCatalog
    ROOT = Rails.root.join("storage", "gtfs")
    DOWNLOADS_DIR = ROOT.join("downloads")
    EXTRACTED_DIR = ROOT.join("extracted")
    CACHE_DIR = ROOT.join("cache")
    CACHE_PATH = CACHE_DIR.join("vienna_lines.json")
    STOPS_CACHE_PATH = CACHE_DIR.join("vienna_stops.json")
    VIENNA_BOUNDS = {
      min_lat: 48.08,
      max_lat: 48.35,
      min_lng: 16.12,
      max_lng: 16.62
    }.freeze
    REQUIRED_FILES = %w[routes.txt trips.txt shapes.txt stops.txt stop_times.txt].freeze
    SOURCES = {
      wiener_linien: {
        key: :wiener_linien,
        label: "Wiener Linien",
        url: "http://www.wienerlinien.at/ogd_realtime/doku/ogd/gtfs/gtfs.zip",
        archive_path: DOWNLOADS_DIR.join("wiener_linien_gtfs.zip"),
        extract_dir: EXTRACTED_DIR.join("wiener_linien")
      },
      oebb: {
        key: :oebb,
        label: "OEBB",
        url: "https://static.web.oebb.at/open-data/soll-fahrplan-gtfs/GTFS_Fahrplan_2026.zip",
        archive_path: DOWNLOADS_DIR.join("oebb_gtfs_2026.zip"),
        extract_dir: EXTRACTED_DIR.join("oebb")
      }
    }.freeze

    module_function

    def source(key)
      SOURCES.fetch(key.to_sym)
    end

    def sources
      SOURCES.values
    end
  end
end
