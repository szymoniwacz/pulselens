require "rails_helper"
require "securerandom"

RSpec.describe "ClickHouse event storage", :integration do
  let(:client) { ClickhouseClient.new }
  let(:application_id) { SecureRandom.uuid }
  let(:event_id) { SecureRandom.uuid }
  let(:name) { "purchase' OR 1=1 --\\\t\n" }
  let(:properties) { { "nested" => [ 1, true, nil, { "text" => "żółć" } ] } }
  let(:event) do
    {
      application_id: application_id,
      event_id: event_id,
      name: name,
      user_id: "synthetic-user",
      occurred_at: Time.iso8601("2026-11-24T12:00:00.123+01:00"),
      received_at: Time.iso8601("2026-11-24T11:00:01.456Z"),
      platform: "ios",
      country: "PL",
      properties: properties
    }
  end

  it "applies versioned setup repeatedly and preserves inserted data, bindings and millisecond UTC values" do
    expect(ClickhouseSchema.new.apply).to be(true)
    expect(client.insert_events([ event ])).to be(true)
    expect(ClickhouseSchema.new.apply).to be(true)

    rows = client.query(<<~SQL, bindings: { application: application_id, event_name: name })
      SELECT application_id, event_id, name, user_id, occurred_at, received_at, platform, country, properties
      FROM events
      WHERE application_id = {application:UUID} AND name = {event_name:String}
    SQL
    expect(rows.length).to eq(1)
    expect(rows.first).to include(
      "application_id" => application_id, "event_id" => event_id, "name" => name,
      "user_id" => "synthetic-user", "occurred_at" => "2026-11-24 11:00:00.123",
      "received_at" => "2026-11-24 11:00:01.456", "platform" => "ios", "country" => "PL"
    )
    expect(JSON.parse(rows.first.fetch("properties"))).to eq(properties)
    expect(client.query("SELECT event_id FROM events WHERE application_id = {application:UUID}",
                        bindings: { application: SecureRandom.uuid })).to be_empty

    expect(client.insert_events([ event ])).to be(true)
    count = client.query("SELECT count() AS count FROM events WHERE application_id = {application:UUID}",
                         bindings: { application: application_id }).first.fetch("count")
    expect(count.to_i).to eq(2)
  end

  it "redacts real server errors and rejected credentials" do
    expect { client.query("SELECT missing_column FROM events") }.to raise_error(ClickhouseClient::Unavailable) do |error|
      expect(error.message).not_to include("missing_column", ENV.fetch("CLICKHOUSE_PASSWORD"))
      expect(error.cause).to be_nil
    end
    rejected = ClickhouseClient.new(password: "synthetic-invalid-password")
    expect { rejected.query("SELECT 1") }.to raise_error(ClickhouseClient::Unavailable) do |error|
      expect(error.message).not_to include("synthetic-invalid-password")
      expect(error.cause).to be_nil
    end
  end
end
