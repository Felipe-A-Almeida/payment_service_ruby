FactoryBot.define do
  factory :idempotency_key do
    sequence(:key) { |n| "idem_key_#{n}_#{SecureRandom.hex(4)}" }
    request_fingerprint { Digest::SHA256.hexdigest(SecureRandom.hex) }
    status { :processing }

    trait :completed do
      status { :completed }
      response_status { 201 }
      response_body { { id: 1, status: "succeeded" }.to_json }
    end
  end
end
