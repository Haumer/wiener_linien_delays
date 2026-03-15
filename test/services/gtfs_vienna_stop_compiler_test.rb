require "test_helper"

class GtfsViennaStopCompilerTest < ActiveSupport::TestCase
  test "builds Vienna network stops from extracted GTFS sources" do
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

    payload = Gtfs::ViennaStopCompiler.new(sources: sources).call

    assert_equal true, payload[:available]
    assert_equal 2, payload.dig(:meta, :stop_count)

    oper = payload[:stops].find { |stop| stop[:name] == "Wien Oper" }
    assert_equal "tram", oper[:primary_category]
    assert_equal %w[13A 2], oper[:lines].map { |line| line[:line] }.sort

    hbf = payload[:stops].find { |stop| stop[:name] == "Wien Hbf" }
    assert_equal ["RJX 860", "S80"], hbf[:lines].map { |line| line[:line] }.sort
    assert_equal %w[rail sbahn], hbf[:categories].map { |category| category[:key] }.sort
  end
end
