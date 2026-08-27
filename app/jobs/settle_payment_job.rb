# Simulates the asynchronous "settlement" step a real gateway would report
# back later (e.g. via webhook). Sidekiq guarantees at-least-once execution,
# meaning this job can run more than once for the same payment_id (retries,
# deploys, etc.) — it must be idempotent on its own, independent of the
# HTTP-level Idempotency-Key protocol.
class SettlePaymentJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3

  def perform(payment_id)
    payment = Payment.find_by(id: payment_id)
    return if payment.nil?

    # Only transition succeeded -> settled. Re-running this on an
    # already-settled (or failed) payment is a safe no-op.
    return unless payment.succeeded?

    payment.update!(status: :settled)
  end
end
