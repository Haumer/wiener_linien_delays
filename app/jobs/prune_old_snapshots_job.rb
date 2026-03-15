class PruneOldSnapshotsJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = 48.hours.ago
    summary_cutoff = 30.days.ago

    TransitSnapshot.where(fetched_at: ...cutoff).destroy_all
    LineHealthSummary.where(recorded_at: ...summary_cutoff).delete_all
  end
end
