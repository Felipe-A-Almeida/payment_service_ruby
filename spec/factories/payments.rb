FactoryBot.define do
  factory :payment do
    idempotency_key
    amount_cents { 5000 }
    currency { "usd" }
    description { "Portfolio demo charge" }
    status { :succeeded }
    card_last4 { "4242" }
    gateway_reference { "ch_#{SecureRandom.hex(12)}" }
    processed_at { Time.current }
  end
end
