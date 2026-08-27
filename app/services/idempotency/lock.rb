module Idempotency
  # A Redis-based distributed lock keyed by the idempotency key.
  #
  # This is purely a performance/UX optimization: it lets a second concurrent
  # request with the same Idempotency-Key wait for the first one to finish and
  # then replay its cached response, instead of racing it into the database.
  # Correctness does NOT depend on this lock — the unique index on
  # idempotency_keys.key (see IdempotencyKey) is what actually guarantees a
  # charge is never processed twice, even if Redis is unavailable or the lock
  # expires mid-request.
  class Lock
    class LockTimeoutError < StandardError; end

    UNLOCK_SCRIPT = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    LUA

    def initialize(redis_pool: REDIS_POOL, ttl: 10, wait_timeout: 8, retry_delay: 0.1)
      @redis_pool = redis_pool
      @ttl = ttl
      @wait_timeout = wait_timeout
      @retry_delay = retry_delay
    end

    # Waits (polling) for the lock on `key`, yields while holding it, then
    # releases it. Raises LockTimeoutError if the lock is still held by
    # someone else after `wait_timeout` seconds.
    def with_lock(key)
      token = SecureRandom.hex(16)
      lock_key = "idempotency:lock:#{key}"

      raise LockTimeoutError, "Timed out waiting for lock on #{key}" unless acquire(lock_key, token)

      begin
        yield
      ensure
        release(lock_key, token)
      end
    end

    private

    def acquire(lock_key, token)
      deadline = monotonic_now + @wait_timeout

      loop do
        acquired = @redis_pool.with { |redis| redis.set(lock_key, token, nx: true, px: (@ttl * 1000).to_i) }
        return true if acquired
        return false if monotonic_now >= deadline

        sleep @retry_delay
      end
    end

    # Only deletes the key if it still holds our token, so we never release a
    # lock that expired and was already re-acquired by another process.
    def release(lock_key, token)
      @redis_pool.with { |redis| redis.eval(UNLOCK_SCRIPT, keys: [ lock_key ], argv: [ token ]) }
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
