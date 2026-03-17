class AddCityToTransitTables < ActiveRecord::Migration[7.1]
  def change
    add_column :transit_snapshots, :city, :string, null: false, default: "wien"
    add_column :vehicle_positions, :city, :string, null: false, default: "wien"
    add_column :line_health_summaries, :city, :string, null: false, default: "wien"
    add_column :stop_delay_records, :city, :string, null: false, default: "wien"

    add_index :transit_snapshots, [:city, :fetched_at]
    add_index :line_health_summaries, [:city, :recorded_at]
    add_index :line_health_summaries, [:city, :line, :recorded_at]
  end
end
