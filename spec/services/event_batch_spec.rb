require "rails_helper"

RSpec.describe EventBatch do
  let(:id) { "00000000-0000-0000-0000-000000000001" }
  let(:received) { Time.utc(2026, 11, 25, 12) }
  let(:event) do
    { "event_id" => "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "name" => "open", "user_id" => "synthetic-user",
      "occurred_at" => "2026-11-02T00:00:00.123999+01:00" }
  end

  def rows(payload)
    described_class.new(payload: payload, application_id: id, received_at: received).rows
  end

  def invalid(payload, field, index = nil)
    expect { rows(payload) }.to raise_error(described_class::Invalid) do |error|
      expect([ error.field, error.index ]).to eq([ field, index ])
    end
  end

  it "normalizes UUID and UTC milliseconds, injects server fields, and defaults absent values only" do
    expect(rows("events" => [ event.merge("unrecognized" => "ignored") ])).to eq([
      { application_id: id, event_id: event.fetch("event_id").downcase, name: "open", user_id: "synthetic-user",
        occurred_at: Time.iso8601("2026-11-01T23:00:00.123Z"), received_at: received,
        platform: "unknown", country: "unknown", properties: {} }
    ])
    explicit = event.merge("platform" => "ios", "country" => "PL", "properties" => { "nested" => [ true, nil, "ż" ] })
    expect(rows("events" => [ explicit ]).first).to include(platform: "ios", country: "PL", properties: explicit.fetch("properties"))
  end

  it "accepts 1 and 1000 events but rejects 0 and 1001" do
    [ 1, 1000 ].each { |count| expect(rows("events" => Array.new(count, event)).size).to eq(count) }
    [ 0, 1001 ].each { |count| invalid({ "events" => Array.new(count, event) }, "events") }
  end

  it "enforces exact UTF-8 field and serialized JSON byte limits" do
    overhead = JSON.generate("text" => "").bytesize
    properties = { "text" => "x" * (16 * 1024 - overhead) }
    boundary = event.merge("name" => "ą" * 64, "user_id" => "ą" * 128, "properties" => properties)
    expect(rows("events" => [ boundary ]).first).to include(name: boundary.fetch("name"), user_id: boundary.fetch("user_id"), properties: properties)
    { "name" => "ą" * 64 + "x", "user_id" => "ą" * 128 + "x", "properties" => { "text" => properties.fetch("text") + "x" } }.each do |field, value|
      invalid({ "events" => [ event, boundary.merge(field => value) ] }, field, 1)
    end
  end

  it "rejects wrong root, events and event types" do
    [ nil, [], true, "text", {}, { "events" => nil }, { "events" => {} }, { "events" => "text" } ].each do |payload|
      invalid(payload, "events")
    end
    [ nil, [], true, "text", 1 ].each { |value| invalid({ "events" => [ event, value ] }, "events", 1) }
  end

  it "rejects reserved fields at both envelope and event level even when null" do
    %w[application_id received_at].each do |field|
      invalid({ "events" => [ event ], field => nil }, field)
      invalid({ "events" => [ event, event.merge(field => nil) ] }, field, 1)
    end
  end

  it "rejects invalid or null fields without echoing supplied values" do
    {
      "event_id" => [ nil, "not-a-uuid", 7, [] ],
      "name" => [ nil, "", " ", 7, {}, "\xff".b.force_encoding("UTF-8") ],
      "user_id" => [ nil, "", " ", [], true ],
      "occurred_at" => [ nil, 1, "2026-11-01", "2026-11-01T00:00:00", "2026-02-30T00:00:00Z", "2026-11-01T24:00:00Z",
                         "2026-11-01T00:00:60Z", "2026-11-01T00:00:00+24:00", "1899-12-31T00:00:00Z", "2300-01-01T00:00:00Z" ],
      "platform" => [ nil, "", "IOS", "desktop", [] ], "country" => [ nil, "", "pl", "ZZ", {} ],
      "properties" => [ nil, [], "text", 1, true, { "number" => Float::INFINITY } ]
    }.each do |field, values|
      values.each { |value| invalid({ "events" => [ event, event.merge(field => value) ] }, field, 1) }
    end
  end
end
