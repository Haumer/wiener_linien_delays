require "test_helper"

class GtfsViennaLineCompilerTest < ActiveSupport::TestCase
  test "builds Vienna route overlays from extracted GTFS sources" do
    sources = [
      {
        key: :wiener_linien,
        label: "Wiener Linien",
        extract_dir: Rails.root.join("test/fixtures/files/gtfs/wiener_linien")
      },
      {
        key: :oebb,
        label: "OEBB",
        extract_dir: Rails.root.join("test/fixtures/files/gtfs/oebb")
      }
    ]

    payload = Gtfs::ViennaLineCompiler.new(sources: sources).call

    assert_equal "FeatureCollection", payload[:type]
    assert_equal true, payload[:available]
    assert_equal 4, payload.dig(:meta, :line_count)

    categories = payload[:features].map { |feature| feature.dig(:properties, :category) }.tally
    assert_equal({ "bus" => 1, "rail" => 1, "sbahn" => 1, "tram" => 1 }, categories)

    tram = payload[:features].find { |feature| feature.dig(:properties, :line) == "2" }
    assert_equal "Wiener Linien", tram.dig(:properties, :source)
    assert_equal "tram", tram.dig(:properties, :category)
    assert_equal "LineString", tram.dig(:geometry, :type)
    assert_operator tram.dig(:geometry, :coordinates).length, :>=, 2

    sbahn = payload[:features].find { |feature| feature.dig(:properties, :line) == "S80" }
    assert_equal "sbahn", sbahn.dig(:properties, :category)
    assert_equal "s80", sbahn.dig(:properties, :line_token)
  end
end
