require "digest"
require "securerandom"

module ApplicationApiKey
  TOKEN_PATTERN = /\A[0-9a-f]{64}\z/
  BEARER_PATTERN = /\A(?i:Bearer) +([0-9a-f]{64})\z/

  def self.generate
    SecureRandom.hex(32)
  end

  def self.digest(key)
    Digest::SHA256.hexdigest(key)
  end

  def self.from_authorization(value)
    return unless value.is_a?(String) && value.ascii_only?

    BEARER_PATTERN.match(value)&.[](1)
  end
end
