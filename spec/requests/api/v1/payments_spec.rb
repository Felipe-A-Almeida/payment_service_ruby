require "rails_helper"

RSpec.describe "Api::V1::Payments", type: :request do
  let(:idempotency_key) { "test-key-#{SecureRandom.hex(8)}" }
  let(:valid_payload) do
    { payment: { amount_cents: 5000, currency: "usd", description: "Portfolio demo", card_number: "4242424242424242" } }
  end

  def post_payment(payload = valid_payload, key: idempotency_key)
    post "/api/v1/payments", params: payload, headers: { "Idempotency-Key" => key }, as: :json
  end

  describe "POST /api/v1/payments" do
    it "requires the Idempotency-Key header" do
      post "/api/v1/payments", params: valid_payload, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json["error"]).to eq("missing_idempotency_key_header")
    end

    it "creates a payment and returns 201" do
      post_payment

      expect(response).to have_http_status(:created)
      expect(json["status"]).to eq("succeeded")
      expect(response.headers["Idempotent-Replay"]).to eq("false")
      expect(Payment.count).to eq(1)
    end

    it "declines simulated test cards ending in 0002" do
      payload = valid_payload.deep_merge(payment: { card_number: "4000000000000002" })

      post_payment(payload)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["status"]).to eq("failed")
      expect(json["failure_reason"]).to eq("card_declined")
    end

    it "replays the original response for a retried request instead of charging twice" do
      post_payment
      first_body = json

      post_payment

      expect(response).to have_http_status(:created)
      expect(json).to eq(first_body)
      expect(response.headers["Idempotent-Replay"]).to eq("true")
      expect(Payment.count).to eq(1)
    end

    it "rejects reusing the same Idempotency-Key with a different payload" do
      post_payment

      post_payment(valid_payload.deep_merge(payment: { amount_cents: 999 }))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("idempotency_key_reused_with_different_params")
      expect(Payment.count).to eq(1)
    end

    it "returns 400 when the payment params are missing" do
      post "/api/v1/payments", params: {}, headers: { "Idempotency-Key" => idempotency_key }, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/payments/:id" do
    it "returns the payment" do
      payment = create(:payment)

      get "/api/v1/payments/#{payment.id}"

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(payment.id)
    end

    it "returns 404 for an unknown payment" do
      get "/api/v1/payments/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  def json
    JSON.parse(response.body)
  end
end
