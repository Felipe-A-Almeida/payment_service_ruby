require "rails_helper"

RSpec.describe Idempotency::Lock do
  let(:key) { "lock-spec-#{SecureRandom.hex(8)}" }

  after do
    REDIS_POOL.with { |redis| redis.del("idempotency:lock:#{key}") }
  end

  it "runs the block while holding the lock" do
    ran = false

    described_class.new.with_lock(key) { ran = true }

    expect(ran).to eq(true)
  end

  it "releases the lock after the block finishes" do
    described_class.new.with_lock(key) { }

    held = REDIS_POOL.with { |redis| redis.get("idempotency:lock:#{key}") }
    expect(held).to be_nil
  end

  it "releases the lock even if the block raises" do
    expect {
      described_class.new.with_lock(key) { raise "boom" }
    }.to raise_error("boom")

    held = REDIS_POOL.with { |redis| redis.get("idempotency:lock:#{key}") }
    expect(held).to be_nil
  end

  it "raises LockTimeoutError when the lock is already held and doesn't free up in time" do
    lock = described_class.new(wait_timeout: 0.3, retry_delay: 0.05)
    REDIS_POOL.with { |redis| redis.set("idempotency:lock:#{key}", "someone-else", px: 5000) }

    expect {
      lock.with_lock(key) { }
    }.to raise_error(described_class::LockTimeoutError)
  end

  it "lets a second waiter through once the first holder releases the lock" do
    lock = described_class.new(wait_timeout: 2, retry_delay: 0.05)
    order = []

    first = Thread.new do
      lock.with_lock(key) do
        order << :first_acquired
        sleep 0.2
      end
      order << :first_released
    end

    sleep 0.05 # give the first thread a head start so it wins the race
    second = Thread.new do
      lock.with_lock(key) { order << :second_acquired }
    end

    [ first, second ].each(&:join)

    expect(order).to eq([ :first_acquired, :first_released, :second_acquired ])
  end
end
