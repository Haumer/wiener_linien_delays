require "test_helper"

class LineHealthSummaryTest < ActiveSupport::TestCase
  setup do
    @snapshot = TransitSnapshot.create!(city: "wien", fetched_at: Time.current, vehicle_count: 10)
    LineHealthSummary.create!(
      city: "wien", line: "2", category: "tram", category_color: "#e53935",
      recorded_at: @snapshot.fetched_at, vehicle_count: 5,
      avg_delay_seconds: 90, max_delay_seconds: 180, stalled_count: 0, status: "ok"
    )
    LineHealthSummary.create!(
      city: "graz", line: "1", category: "tram", category_color: "#e53935",
      recorded_at: @snapshot.fetched_at, vehicle_count: 3,
      avg_delay_seconds: 300, max_delay_seconds: 600, stalled_count: 1, status: "major_delay"
    )
  end

  test "current_for scopes by city" do
    wien = LineHealthSummary.current_for("wien")
    assert_equal 1, wien.count
    assert_equal "2", wien.first.line

    graz = LineHealthSummary.current_for("graz")
    assert_equal 1, graz.count
    assert_equal "1", graz.first.line
  end

  test "delayed? returns true for non-ok status" do
    ok = LineHealthSummary.current_for("wien").first
    delayed = LineHealthSummary.current_for("graz").first
    assert_not ok.delayed?
    assert delayed.delayed?
  end

  test "delay_minutes converts seconds to minutes" do
    line = LineHealthSummary.current_for("wien").first
    assert_equal 1.5, line.delay_minutes
  end
end
