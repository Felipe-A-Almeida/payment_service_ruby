require "rails_helper"

RSpec.describe SettlePaymentJob do
  it "settles a succeeded payment" do
    payment = create(:payment, status: :succeeded)

    described_class.new.perform(payment.id)

    expect(payment.reload).to be_settled
  end

  it "is a no-op when run twice (Sidekiq's at-least-once delivery)" do
    payment = create(:payment, status: :succeeded)

    2.times { described_class.new.perform(payment.id) }

    expect(payment.reload).to be_settled
  end

  it "does not settle a failed payment" do
    payment = create(:payment, status: :failed, failure_reason: "card_declined")

    described_class.new.perform(payment.id)

    expect(payment.reload).to be_failed
  end

  it "is a no-op for a payment that no longer exists" do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end
end
