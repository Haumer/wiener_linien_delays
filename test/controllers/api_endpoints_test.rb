require "test_helper"

class ApiEndpointsTest < ActionDispatch::IntegrationTest
  test "vehicles endpoint is public" do
    payload = {
      vehicles: [{ id: "tram-1", name: "Tram 62" }],
      counts: { tram: 1, bus: 0, sbahn: 0, obus: 0, rail: 0 },
      fetched_at: "2026-03-13T19:42:03+01:00"
    }

    with_stubbed_constructor(OebbVehicleService, stub_service(payload)) do
      get api_vehicles_path, as: :json
    end

    assert_response :success
    assert_equal "Tram 62", JSON.parse(response.body).dig("vehicles", 0, "name")
  end

  test "lines endpoint is public" do
    payload = {
      type: "FeatureCollection",
      available: true,
      meta: { line_count: 1, sources: ["Wiener Linien"] },
      features: [
        {
          type: "Feature",
          properties: { line: "2", category: "tram" },
          geometry: { type: "LineString", coordinates: [[16.36, 48.2], [16.37, 48.21]] }
        }
      ]
    }

    with_stubbed_constructor(LineOverlayService, stub_service(payload)) do
      get api_lines_path, as: :json
    end

    assert_response :success
    assert_equal "2", JSON.parse(response.body).dig("features", 0, "properties", "line")
  end

  test "stops endpoint is public" do
    payload = {
      available: true,
      meta: { stop_count: 1, sources: ["Wiener Linien"] },
      stops: [
        {
          id: "wiener_linien:wl_stop_vienna",
          name: "Wien Oper",
          primary_category: "tram",
          lines: [{ line: "2", category: "tram" }]
        }
      ],
      count: 1
    }

    with_stubbed_constructor(StopOverlayService, stub_service(payload)) do
      get api_stops_path, as: :json
    end

    assert_response :success
    assert_equal "Wien Oper", JSON.parse(response.body).dig("stops", 0, "name")
  end

  test "stops departures require a lid" do
    get api_stops_departures_path, as: :json

    assert_response :bad_request
    assert_equal "Stop lid is required", JSON.parse(response.body)["error"]
  end

  private

  def stub_service(payload)
    Struct.new(:payload) do
      def call(*)
        payload
      end
    end.new(payload)
  end

  def with_stubbed_constructor(klass, replacement)
    original_new = klass.method(:new)
    klass.singleton_class.send(:define_method, :new) { |*| replacement }
    yield
  ensure
    klass.singleton_class.send(:define_method, :new, original_new)
  end
end
