class CreateStopDelayRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :stop_delay_records do |t|
      t.references :transit_snapshot, null: false, foreign_key: true
      t.string :line, null: false
      t.string :category, null: false
      t.string :direction
      t.string :stop_name, null: false
      t.integer :delay_seconds, null: false, default: 0
      t.integer :stop_sequence, null: false, default: 0
    end

    add_index :stop_delay_records, [:line, :stop_name]
    add_index :stop_delay_records, [:line, :transit_snapshot_id]
  end
end
