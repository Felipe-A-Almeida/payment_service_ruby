require "rails_helper"

RSpec.describe Payment, type: :model do
  it "requires a positive amount_cents" do
    payment = build(:payment, amount_cents: 0)
    expect(payment).not_to be_valid

    payment.amount_cents = -100
    expect(payment).not_to be_valid

    payment.amount_cents = 100
    expect(payment).to be_valid
  end

  it "enforces one payment per idempotency key at the database level" do
    idempotency_key = create(:idempotency_key)
    create(:payment, idempotency_key: idempotency_key)
    duplicate = build(:payment, idempotency_key: idempotency_key)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "#amount" do
    it "converts cents to a decimal amount" do
      payment = build(:payment, amount_cents: 1050)
      expect(payment.amount).to eq(10.5)
    end
  end
end
