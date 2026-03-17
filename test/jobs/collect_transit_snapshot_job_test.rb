require "test_helper"

class FakeVehicleService
  def initialize(data)
    @data = data
  end

  def call
    @data
  end
end

class CollectTransitSnapshotJobTest < ActiveJob::TestCase
  setup do
    @vehicle_data = {
      vehicles: [
        {
          id: "journey_1", name: "2", line: "2",
          category: "tram", category_label: "Tram", category_color: "#e53935",
          lat: 48.21, lng: 16.37, direction: "Ottakring", progress: 50,
          next_stops: [
            { name: "Rathaus", lat: 48.21, lng: 16.36,
              realtime_at: 2.minutes.from_now.iso8601, scheduled_at: Time.current.iso8601 },
            { name: "Volkstheater", lat: 48.20, lng: 16.35,
              realtime_at: 5.minutes.from_now.iso8601, scheduled_at: 3.minutes.from_now.iso8601 }
          ]
        }
      ],
      counts: { tram: 1 },
      fetched_at: Time.current.iso8601
    }

    fake = FakeVehicleService.new(@vehicle_data)
    @original_new = OebbVehicleService.method(:new)
    OebbVehicleService.define_singleton_method(:new) { |**_| fake }
    @original_env = ENV["TRANSIT_CITIES"]
    ENV["TRANSIT_CITIES"] = "wien"
  end

  teardown do
    OebbVehicleService.define_singleton_method(:new, @original_new)
    ENV["TRANSIT_CITIES"] = @original_env
  end

  test "creates snapshot, positions, stop records, and health" do
    assert_difference -> { TransitSnapshot.count } => 1,
                      -> { VehiclePosition.count } => 1,
                      -> { StopDelayRecord.count } => 2,
                      -> { LineHealthSummary.count } => 1 do
      CollectTransitSnapshotJob.perform_now
    end

    snapshot = TransitSnapshot.last
    assert_equal "wien", snapshot.city
    assert_equal 1, snapshot.vehicle_count

    vp = VehiclePosition.last
    assert_equal "2", vp.line
    assert_equal "wien", vp.city
  end

  test "stall detection logic" do
    job = CollectTransitSnapshotJob.new
    assert job.send(:stalled?, { lat: 48.21, lng: 16.37 }, { lat: 48.21, lng: 16.37 })
    assert_not job.send(:stalled?, { lat: 48.21, lng: 16.37 }, { lat: 48.22, lng: 16.37 })
    assert_not job.send(:stalled?, { lat: 48.21, lng: 16.37 }, nil)
  end
end
