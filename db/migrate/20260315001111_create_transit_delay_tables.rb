class CreateTransitDelayTables < ActiveRecord::Migration[7.1]
  def change
    create_table :transit_snapshots do |t|
      t.datetime :fetched_at, null: false
      t.integer :vehicle_count, null: false, default: 0
      t.timestamps
    end

    add_index :transit_snapshots, :fetched_at

    create_table :vehicle_positions do |t|
      t.references :transit_snapshot, null: false, foreign_key: true
      t.string :journey_id, null: false
      t.string :line, null: false
      t.string :category, null: false
      t.string :direction
      t.decimal :lat, precision: 10, scale: 7
      t.decimal :lng, precision: 10, scale: 7
      t.integer :delay_seconds
      t.boolean :stalled, null: false, default: false
    end

    add_index :vehicle_positions, [:line, :transit_snapshot_id]
    add_index :vehicle_positions, [:journey_id, :transit_snapshot_id]

    create_table :line_health_summaries do |t|
      t.string :line, null: false
      t.string :category, null: false
      t.string :category_color, null: false
      t.datetime :recorded_at, null: false
      t.integer :vehicle_count, null: false, default: 0
      t.integer :avg_delay_seconds, null: false, default: 0
      t.integer :max_delay_seconds, null: false, default: 0
      t.integer :stalled_count, null: false, default: 0
      t.string :status, null: false, default: "ok"
    end

    add_index :line_health_summaries, [:line, :recorded_at]
    add_index :line_health_summaries, :recorded_at
    add_index :line_health_summaries, :status
  end
end
