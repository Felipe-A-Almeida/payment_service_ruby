# Stores one row per unique `Idempotency-Key` header ever seen, so a retried
# request (network timeout, client bug, at-least-once delivery) replays the
# original response instead of re-running side effects like charging a card.
class IdempotencyKey < ApplicationRecord
  has_one :payment, dependent: :destroy

  enum :status, { processing: 0, completed: 1 }, default: :processing

  validates :key, presence: true, uniqueness: true
  validates :request_fingerprint, presence: true

  def response_body_json
    return nil if response_body.blank?

    JSON.parse(response_body)
  end

  def mark_completed!(status:, body:)
    update!(
      status: :completed,
      response_status: status,
      response_body: body.to_json
    )
  end
end
