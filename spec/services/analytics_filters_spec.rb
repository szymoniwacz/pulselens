require "rails_helper"

RSpec.describe AnalyticsFilters do
  let(:range) { { from: "2026-11-01T00:00:00Z", to: "2026-11-02T00:00:00Z" } }

  it "normalizes offsets and excludes an exact-midnight end date" do
    filters = described_class.new(from: "2026-11-01T01:00:00+01:00", to: "2026-11-02T01:00:00+01:00")
    expect(filters.from).to eq(Time.utc(2026, 11, 1))
    expect(filters.to).to eq(Time.utc(2026, 11, 2))
    expect(filters.dates.to_a).to eq([ Date.new(2026, 11, 1) ])
  end

  it "ceil-rounds both timestamp bounds without changing the intersected dates" do
    filters = described_class.new(from: "2026-11-01T23:59:59.9991Z", to: "2026-11-02T00:00:00.0001Z")
    expect(filters.from_milliseconds).to eq(Time.utc(2026, 11, 2))
    expect(filters.to_milliseconds).to eq(Time.iso8601("2026-11-02T00:00:00.001Z"))
    expect(filters.dates.to_a).to eq([ Date.new(2026, 11, 1), Date.new(2026, 11, 2) ])
  end

  it "accepts exactly 90 elapsed days and rejects a longer or nonpositive range" do
    expect(described_class.new(from: "2026-01-01T12:00:00Z", to: "2026-04-01T12:00:00Z").dates.count).to eq(91)
    [ "2026-01-01T12:00:00Z", "2025-12-31T12:00:00Z", "2026-04-01T12:00:00.0001Z" ].each do |ending|
      expect { described_class.new(from: "2026-01-01T12:00:00Z", to: ending) }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects missing, invalid, out-of-range and timezone-less timestamps" do
    [ nil, "", [], "2026-11-01", "2026-11-01T00:00:00", "2026-02-30T00:00:00Z",
      "2026-11-01T24:00:00Z", "2026-11-01T00:60:00Z", "2026-11-01T00:00:60Z", "2026-11-01T00:00:00+25:00",
      "1899-12-31T00:00:00Z", "2300-01-01T00:00:00Z" ].each do |value|
      expect { described_class.new(**range.merge(from: value)) }.to raise_error(described_class::Invalid, "Invalid from timestamp")
      expect { described_class.new(**range.merge(to: value)) }.to raise_error(described_class::Invalid, "Invalid to timestamp")
    end
  end

  it "validates optional filters including byte limits, nulls and unknown sentinels" do
    expect(described_class.new(**range, name: "ą" * 64, platform: "unknown", country: "unknown").name.bytesize).to eq(128)
    expect(described_class.new(**range, country: "PL").country).to eq("PL")
    [ { name: "" }, { name: " " }, { name: [] }, { name: nil }, { name: "ą" * 65 },
      { platform: "desktop" }, { platform: nil }, { platform: [] },
      { country: "pl" }, { country: "ZZ" }, { country: "XXX" }, { country: nil }, { country: {} } ].each do |extra|
      expect { described_class.new(**range, **extra) }.to raise_error(described_class::Invalid)
    end
  end
end
