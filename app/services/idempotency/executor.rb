module Idempotency
  # Orchestrates the idempotency-key protocol around an arbitrary block of
  # "do the actual work" code:
  #
  #   1. If a *completed* record already exists for this key, replay its
  #      stored response instead of running the block again.
  #   2. Otherwise, take the distributed lock for this key (see Lock) so that
  #      concurrent retries queue up instead of racing each other.
  #   3. Find-or-create the IdempotencyKey row (protected by a DB unique
  #      index as the final correctness guarantee — see IdempotencyKey).
  #   4. Run the block exactly once, store its result on the record, and
  #      return it.
  #
  # Any request reusing the same key with a different payload raises
  # KeyReusedWithDifferentParamsError instead of silently replaying or
  # re-running.
  class Executor
    Result = Struct.new(:status, :body, :replayed, keyword_init: true)

    class KeyReusedWithDifferentParamsError < StandardError; end

    def initialize(key:, fingerprint:, lock: Idempotency::Lock.new)
      @key = key
      @fingerprint = fingerprint
      @lock = lock
    end

    def call
      # Rails caches identical SELECTs within a single request. Without this,
      # a request that blocks on the lock below and then re-queries the same
      # row could be served a stale "not completed yet" snapshot from before
      # it waited, and would go on to redo the work the winner already did.
      ActiveRecord::Base.uncached do
        existing = IdempotencyKey.find_by(key: @key)
        next replay(existing) if existing&.completed?

        @lock.with_lock(@key) do
          record = find_or_create_record!
          next replay(record) if record.completed?

          status, body = yield(record)
          record.mark_completed!(status: status, body: body)
          # Round-trip through JSON so a fresh response and a replayed one are
          # shaped identically (string keys either way).
          Result.new(status: status, body: record.response_body_json, replayed: false)
        end
      end
    end

    private

    def find_or_create_record!
      IdempotencyKey.find_by(key: @key) || create_record!
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Lost a race with another process that inserted this key between our
      # SELECT and INSERT (raised as RecordNotUnique by the DB's unique index,
      # or as RecordInvalid if Rails' own uniqueness validation caught it
      # first). Either way, the unique index is the tiebreaker; fall back to
      # reading what the winner wrote.
      record = IdempotencyKey.find_by!(key: @key)
      verify_fingerprint!(record)
      record
    end

    def create_record!
      IdempotencyKey.create!(
        key: @key,
        request_fingerprint: @fingerprint,
        locked_by: "#{Socket.gethostname}:#{Process.pid}"
      )
    end

    def replay(record)
      verify_fingerprint!(record)
      Result.new(status: record.response_status, body: record.response_body_json, replayed: true)
    end

    def verify_fingerprint!(record)
      return if record.request_fingerprint == @fingerprint

      raise KeyReusedWithDifferentParamsError,
        "Idempotency-Key #{@key} was already used with a different request payload"
    end
  end
end
