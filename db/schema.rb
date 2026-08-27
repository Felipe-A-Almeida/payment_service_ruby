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

ActiveRecord::Schema[8.1].define(version: 2026_08_27_002307) do
  create_table "idempotency_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "locked_by"
    t.string "request_fingerprint", null: false
    t.text "response_body"
    t.integer "response_status"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_idempotency_keys_on_key", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.string "card_last4"
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.string "description"
    t.string "failure_reason"
    t.string "gateway_reference"
    t.integer "idempotency_key_id", null: false
    t.datetime "processed_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key_id"], name: "index_payments_on_idempotency_key_id", unique: true
  end

  add_foreign_key "payments", "idempotency_keys"
end
