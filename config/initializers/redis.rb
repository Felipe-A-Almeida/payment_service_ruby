# Shared connection pool used by Idempotency::Lock. Kept separate from
# Sidekiq's own Redis connection (configured in config/initializers/sidekiq.rb)
# so the two subsystems can be pointed at different Redis instances/DBs in
# production if needed.
REDIS_POOL = ConnectionPool.new(size: ENV.fetch("REDIS_POOL_SIZE", 10).to_i, timeout: 5) do
  Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
end
