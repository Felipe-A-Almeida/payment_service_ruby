class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.string :key, null: false
      t.string :request_fingerprint, null: false
      t.integer :status, null: false, default: 0
      t.integer :response_status
      t.text :response_body
      t.string :locked_by

      t.timestamps
    end
    # The unique index is the source of truth that prevents duplicate charges:
    # even if the Redis lock is bypassed or Redis is down, two concurrent
    # inserts for the same key can't both succeed.
    add_index :idempotency_keys, :key, unique: true
  end
end
