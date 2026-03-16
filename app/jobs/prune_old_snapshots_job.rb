class PruneOldSnapshotsJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = 48.hours.ago
    summary_cutoff = 30.days.ago

    # destroy_all cascades to vehicle_positions and stop_delay_records via FK
    TransitSnapshot.where(fetched_at: ...cutoff).destroy_all
    LineHealthSummary.where(recorded_at: ...summary_cutoff).delete_all
    # Also clean up orphaned stop delay records just in case
    StopDelayRecord.where.not(transit_snapshot_id: TransitSnapshot.select(:id)).delete_all
  end
end
