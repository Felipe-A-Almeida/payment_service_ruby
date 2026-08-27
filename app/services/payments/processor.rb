module Payments
  # Simulates calling out to a real payment gateway: it takes a bit of time
  # and can be declined. Test card numbers ending in one of
  # DECLINE_CARD_SUFFIXES always fail, mirroring how Stripe's test cards work,
  # so the failure path is easy to exercise on purpose.
  class Processor
    DECLINE_CARD_SUFFIXES = %w[0002 0069 0127].freeze

    Result = Struct.new(:payment, :success, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(idempotency_key:, amount_cents:, currency: "usd", description: nil, card_number: nil)
      @idempotency_key = idempotency_key
      @amount_cents = amount_cents
      @currency = currency.presence || "usd"
      @description = description
      @card_number = card_number
    end

    def charge!
      payment = nil

      ActiveRecord::Base.transaction do
        payment = Payment.create!(
          idempotency_key: @idempotency_key,
          amount_cents: @amount_cents,
          currency: @currency,
          description: @description,
          card_last4: @card_number.presence&.last(4),
          status: :pending
        )

        simulate_gateway_latency

        if declined?
          payment.update!(status: :failed, failure_reason: "card_declined", processed_at: Time.current)
        else
          payment.update!(
            status: :succeeded,
            gateway_reference: "ch_#{SecureRandom.hex(12)}",
            processed_at: Time.current
          )
        end
      end

      SettlePaymentJob.perform_in(5.seconds, payment.id) if payment.succeeded?

      Result.new(payment: payment, success: payment.succeeded?)
    rescue ActiveRecord::RecordNotUnique
      # Defense in depth: this would only happen if something upstream
      # (Idempotency::Executor) let two callers reach here for the same
      # idempotency key. Rather than surface a 500, fall back to whatever
      # the other caller actually persisted.
      payment = @idempotency_key.reload.payment
      Result.new(payment: payment, success: payment.succeeded?)
    end

    private

    def declined?
      @card_number.present? && DECLINE_CARD_SUFFIXES.include?(@card_number.last(4))
    end

    def simulate_gateway_latency
      sleep(rand(0.05..0.2)) unless Rails.env.test?
    end
  end
end
