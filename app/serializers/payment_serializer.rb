class PaymentSerializer
  def self.render(payment)
    {
      id: payment.id,
      amount_cents: payment.amount_cents,
      currency: payment.currency,
      description: payment.description,
      status: payment.status,
      failure_reason: payment.failure_reason,
      card_last4: payment.card_last4,
      gateway_reference: payment.gateway_reference,
      processed_at: payment.processed_at,
      created_at: payment.created_at
    }
  end
end
