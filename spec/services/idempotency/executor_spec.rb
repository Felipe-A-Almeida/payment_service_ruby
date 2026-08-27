require "rails_helper"

RSpec.describe Idempotency::Executor do
  let(:key) { "idem_#{SecureRandom.hex(8)}" }
  let(:fingerprint) { Idempotency::RequestFingerprint.generate(method: "POST", path: "/api/v1/payments", params: { amount_cents: 500 }) }

  def build_executor(key: self.key, fingerprint: self.fingerprint)
    described_class.new(key: key, fingerprint: fingerprint)
  end

  it "runs the block and persists the response on first call" do
    result = build_executor.call { |_record| [ 201, { ok: true } ] }

    expect(result.status).to eq(201)
    expect(result.body).to eq({ "ok" => true })
    expect(result.replayed).to eq(false)
    expect(IdempotencyKey.find_by(key: key)).to be_completed
  end

  it "replays the stored response instead of re-running the block for a repeat request" do
    calls = 0
    block = ->(_record) { calls += 1; [ 201, { call: calls } ] }

    first = build_executor.call(&block)
    second = build_executor.call(&block)

    expect(calls).to eq(1)
    expect(second.body).to eq(first.body)
    expect(second.replayed).to eq(true)
  end

  it "raises when the same key is reused with a different payload" do
    build_executor.call { |_record| [ 201, { ok: true } ] }

    other_fingerprint = Idempotency::RequestFingerprint.generate(method: "POST", path: "/api/v1/payments", params: { amount_cents: 999 })

    expect {
      build_executor(fingerprint: other_fingerprint).call { |_record| [ 201, { ok: true } ] }
    }.to raise_error(Idempotency::Executor::KeyReusedWithDifferentParamsError)
  end

  # Regression test for a real bug found while load-testing this project:
  # Rails caches identical SELECTs within one request. A request that reads
  # "key not found yet", then blocks waiting for the lock, then re-reads the
  # same row after another request finished, must NOT be served that first,
  # now-stale answer -- or it will redo the charge. See Executor#call.
  it "is not fooled by a stale per-request query cache" do
    ActiveRecord::Base.connection.cache do
      IdempotencyKey.find_by(key: key) # primes the query cache with "not found"

      other_record = IdempotencyKey.create!(key: key, request_fingerprint: fingerprint)
      other_record.mark_completed!(status: 201, body: { from: "another request" })

      result = build_executor.call { |_record| raise "block re-ran on a stale cached read" }

      expect(result.replayed).to eq(true)
      expect(result.body).to eq("from" => "another request")
    end
  end

  # This is the core correctness guarantee of the whole project: no matter how
  # many requests race in with the *same* Idempotency-Key, the "charge" block
  # only ever runs once, and every caller gets back the exact same response.
  describe "concurrent requests with the same key", use_transactional_tests: false do
    after { IdempotencyKey.delete_all }

    it "executes the block exactly once and returns identical results to every caller" do
      thread_count = 12
      call_count = Concurrent::AtomicFixnum.new(0)
      barrier_ready = Queue.new
      release = Queue.new

      results = Array.new(thread_count)

      threads = Array.new(thread_count) do |i|
        Thread.new do
          barrier_ready << true
          release.pop # all threads start hitting the executor at (almost) the same moment

          results[i] = build_executor.call do |_record|
            call_count.increment
            sleep 0.05 # simulate the "charge the card" gateway latency
            [ 201, { charge_id: SecureRandom.hex(6) } ]
          end
        end
      end

      thread_count.times { barrier_ready.pop }
      thread_count.times { release << true }
      threads.each(&:join)

      expect(call_count.value).to eq(1)
      expect(results.map(&:body).uniq.length).to eq(1)
      expect(IdempotencyKey.where(key: key).count).to eq(1)
    end
  end
end
