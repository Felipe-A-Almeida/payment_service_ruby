module Idempotency
  # Hashes the meaningful parts of a request so we can tell "the client
  # retried the exact same request" apart from "the client reused an
  # Idempotency-Key for a different payload" (a client bug).
  class RequestFingerprint
    def self.generate(method:, path:, params:)
      raw = "#{method.upcase}|#{path}|#{params.to_json}"
      Digest::SHA256.hexdigest(raw)
    end
  end
end
