# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_03_15_001111) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "line_health_summaries", force: :cascade do |t|
    t.string "line", null: false
    t.string "category", null: false
    t.string "category_color", null: false
    t.datetime "recorded_at", null: false
    t.integer "vehicle_count", default: 0, null: false
    t.integer "avg_delay_seconds", default: 0, null: false
    t.integer "max_delay_seconds", default: 0, null: false
    t.integer "stalled_count", default: 0, null: false
    t.string "status", default: "ok", null: false
    t.index ["line", "recorded_at"], name: "index_line_health_summaries_on_line_and_recorded_at"
    t.index ["recorded_at"], name: "index_line_health_summaries_on_recorded_at"
    t.index ["status"], name: "index_line_health_summaries_on_status"
  end

  create_table "transit_snapshots", force: :cascade do |t|
    t.datetime "fetched_at", null: false
    t.integer "vehicle_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fetched_at"], name: "index_transit_snapshots_on_fetched_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vehicle_positions", force: :cascade do |t|
    t.bigint "transit_snapshot_id", null: false
    t.string "journey_id", null: false
    t.string "line", null: false
    t.string "category", null: false
    t.string "direction"
    t.decimal "lat", precision: 10, scale: 7
    t.decimal "lng", precision: 10, scale: 7
    t.integer "delay_seconds"
    t.boolean "stalled", default: false, null: false
    t.index ["journey_id", "transit_snapshot_id"], name: "index_vehicle_positions_on_journey_id_and_transit_snapshot_id"
    t.index ["line", "transit_snapshot_id"], name: "index_vehicle_positions_on_line_and_transit_snapshot_id"
    t.index ["transit_snapshot_id"], name: "index_vehicle_positions_on_transit_snapshot_id"
  end

  add_foreign_key "vehicle_positions", "transit_snapshots"
end
