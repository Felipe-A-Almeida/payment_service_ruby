class Payment < ApplicationRecord
  belongs_to :idempotency_key

  enum :status, { pending: 0, succeeded: 1, failed: 2, settled: 3 }, default: :pending

  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true

  def amount
    amount_cents / 100.0
  end
end
