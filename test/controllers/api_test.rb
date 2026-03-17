require "test_helper"

class ApiCitiesTest < ActionDispatch::IntegrationTest
  test "GET /api/cities returns city list" do
    get "/api/cities"
    assert_response :success
    data = JSON.parse(response.body)
    assert data["cities"].is_a?(Array)
    assert data["cities"].any? { |c| c["key"] == "wien" }
    assert data["cities"].first.key?("name")
    assert data["cities"].first.key?("population")
  end
end

class ApiLineHealthTest < ActionDispatch::IntegrationTest
  setup do
    snapshot = TransitSnapshot.create!(city: "wien", fetched_at: Time.current, vehicle_count: 1)
    LineHealthSummary.create!(
      city: "wien", line: "2", category: "tram", category_color: "#e53935",
      recorded_at: snapshot.fetched_at, vehicle_count: 5,
      avg_delay_seconds: 90, max_delay_seconds: 180, stalled_count: 0, status: "ok"
    )
    LineHealthSummary.create!(
      city: "wien", line: "13A", category: "bus", category_color: "#1e88e5",
      recorded_at: snapshot.fetched_at, vehicle_count: 8,
      avg_delay_seconds: 240, max_delay_seconds: 420, stalled_count: 1, status: "minor_delay"
    )
  end

  test "GET /api/line_health returns lines with summary" do
    get "/api/line_health", params: { city: "wien" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "wien", data["city"]
    assert_equal 2, data["lines"].size
    assert data["summary"]["total_lines"] == 2
  end

  test "GET /api/line_health filters by category" do
    get "/api/line_health", params: { city: "wien", category: "tram" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data["lines"].size
    assert_equal "2", data["lines"].first["line"]
  end

  test "GET /api/line_health/history requires line param" do
    get "/api/line_health/history", params: { city: "wien" }
    assert_response :bad_request
  end

  test "GET /api/line_health/history returns data points" do
    get "/api/line_health/history", params: { city: "wien", line: "2" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "2", data["line"]
    assert data["data_points"].is_a?(Array)
  end
end

class ApiDisruptionsTest < ActionDispatch::IntegrationTest
  setup do
    snapshot = TransitSnapshot.create!(city: "wien", fetched_at: Time.current, vehicle_count: 1)
    LineHealthSummary.create!(
      city: "wien", line: "ok_line", category: "tram", category_color: "#e53935",
      recorded_at: snapshot.fetched_at, vehicle_count: 3,
      avg_delay_seconds: 30, max_delay_seconds: 60, stalled_count: 0, status: "ok"
    )
    LineHealthSummary.create!(
      city: "wien", line: "bad_line", category: "bus", category_color: "#1e88e5",
      recorded_at: snapshot.fetched_at, vehicle_count: 2,
      avg_delay_seconds: 600, max_delay_seconds: 900, stalled_count: 1, status: "disrupted"
    )
  end

  test "GET /api/disruptions returns only disrupted lines" do
    get "/api/disruptions", params: { city: "wien" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data["count"]
    assert_equal "bad_line", data["disruptions"].first["line"]
  end
end

class ApiStopDelaysTest < ActionDispatch::IntegrationTest
  setup do
    snapshot = TransitSnapshot.create!(city: "wien", fetched_at: Time.current, vehicle_count: 1)
    StopDelayRecord.create!(
      transit_snapshot: snapshot, city: "wien", line: "13A", category: "bus",
      direction: "Skodagasse", stop_name: "Neubaugasse", delay_seconds: 180,
      stop_sequence: 0, journey_id: "j1"
    )
    StopDelayRecord.create!(
      transit_snapshot: snapshot, city: "wien", line: "13A", category: "bus",
      direction: "Skodagasse", stop_name: "Westbahnhof", delay_seconds: 60,
      stop_sequence: 1, journey_id: "j1"
    )
  end

  test "GET /api/stop_delays requires line param" do
    get "/api/stop_delays", params: { city: "wien" }
    assert_response :bad_request
  end

  test "GET /api/stop_delays returns per-stop data" do
    get "/api/stop_delays", params: { city: "wien", line: "13A" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "13A", data["line"]
    assert_equal 2, data["stops"].size
    # Sorted by total delay descending
    assert_equal "Neubaugasse", data["stops"].first["stop"]
  end
end

class ApiVehiclesTest < ActionDispatch::IntegrationTest
  setup do
    snapshot = TransitSnapshot.create!(city: "wien", fetched_at: Time.current, vehicle_count: 1)
    VehiclePosition.create!(
      transit_snapshot: snapshot, city: "wien", journey_id: "j1",
      line: "2", category: "tram", direction: "Ottakring",
      lat: 48.21, lng: 16.37, delay_seconds: 120, stalled: false
    )
  end

  test "GET /api/vehicles returns vehicles from latest snapshot" do
    get "/api/vehicles"
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data["vehicles"].size
    assert_equal "2", data["vehicles"].first["line"]
    assert data["fetched_at"].present?
  end
end
