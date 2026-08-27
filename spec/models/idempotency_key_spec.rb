require "rails_helper"

RSpec.describe IdempotencyKey, type: :model do
  it "requires a key" do
    record = build(:idempotency_key, key: nil)
    expect(record).not_to be_valid
    expect(record.errors[:key]).to be_present
  end

  it "requires a request_fingerprint" do
    record = build(:idempotency_key, request_fingerprint: nil)
    expect(record).not_to be_valid
    expect(record.errors[:request_fingerprint]).to be_present
  end

  it "enforces uniqueness of key at the model level" do
    existing = create(:idempotency_key)
    duplicate = build(:idempotency_key, key: existing.key)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:key]).to be_present
  end

  it "enforces uniqueness of key at the database level, independent of validations" do
    existing = create(:idempotency_key)
    duplicate = build(:idempotency_key, key: existing.key)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "#mark_completed!" do
    it "stores the response and flips status to completed" do
      record = create(:idempotency_key)

      record.mark_completed!(status: 201, body: { id: 1 })

      expect(record).to be_completed
      expect(record.response_status).to eq(201)
      expect(record.response_body_json).to eq("id" => 1)
    end
  end
end
