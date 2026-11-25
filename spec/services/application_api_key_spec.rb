require "rails_helper"

RSpec.describe ApplicationApiKey do
  it "generates 256 bits of randomness encoded as 64 lowercase hex characters" do
    expect(SecureRandom).to receive(:hex).with(32).and_call_original
    key = described_class.generate
    expect(key).to match(/\A[0-9a-f]{64}\z/)
    expect(described_class.digest(key)).to eq(Digest::SHA256.hexdigest(key))
  end

  it "extracts only a valid Bearer credential, with a case-insensitive scheme" do
    key = "a" * 64
    expect(described_class.from_authorization("bEaReR #{key}")).to eq(key)
    [ nil, "", "Bearer \xFF".b, key, "Basic #{key}", "Bearer", "Bearer #{key}, #{key}", "Bearer #{key}\n",
      "Bearer #{key.upcase}", "Bearer #{key} ", "Bearer\t#{key}", "Bearer #{key}x" ].each do |header|
      expect(described_class.from_authorization(header)).to be_nil
    end
  end
end
