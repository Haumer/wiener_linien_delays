class AddJourneyIdToStopDelayRecords < ActiveRecord::Migration[7.1]
  def change
    add_column :stop_delay_records, :journey_id, :string
  end
end
