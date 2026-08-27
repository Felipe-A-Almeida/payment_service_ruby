class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :idempotency_key, null: false, foreign_key: true, index: { unique: true }
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.string :description
      t.integer :status, null: false, default: 0
      t.string :failure_reason
      t.string :card_last4
      t.string :gateway_reference
      t.datetime :processed_at

      t.timestamps
    end
  end
end
