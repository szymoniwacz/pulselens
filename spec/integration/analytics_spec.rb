require "rails_helper"
require "securerandom"

RSpec.describe "Analytics API", :integration, type: :request do
  let(:client) { ClickhouseClient.new }
  let(:application_and_key) { Application.issue_key!(name: "Analytics demo") }
  let(:application) { application_and_key.first }
  let(:headers) { { "Authorization" => "Bearer #{application_and_key.last}" } }
  let(:range) { { from: "2026-11-01T12:00:00Z", to: "2026-11-04T00:00:00Z" } }
  let(:malicious_name) { "purchase' OR 1=1 --\\\t\n" }

  def event(application_id, timestamp, name, user, platform = "ios", country = "PL")
    {
      application_id: application_id, event_id: SecureRandom.uuid, name: name, user_id: user,
      occurred_at: Time.iso8601(timestamp), received_at: Time.utc(2026, 11, 25),
      platform: platform, country: country, properties: {}
    }
  end

  def get_analytics(filters = range, authorization = headers)
    get "/api/v1/analytics", params: filters, headers: authorization
  end

  def seed_fixture
    @other, @other_key = Application.issue_key!(name: "Other analytics demo")
    client.insert_events([
      event(application.id, "2026-11-01T11:59:59.999Z", "outside", "outside"),
      event(application.id, "2026-11-01T12:00:00Z", "open", "returning"),
      event(application.id, "2026-11-02T00:30:00+01:00", "purchase", "first", "web", "US"),
      event(application.id, "2026-11-02T23:59:59.999Z", "open", "returning", "android", "US"),
      event(application.id, "2026-11-03T00:00:00Z", "open", "third", "ios", "PL"),
      event(application.id, "2026-11-03T12:00:00Z", "purchase", "third", "ios", "US"),
      event(application.id, "2026-11-04T00:00:00Z", "outside", "outside"),
      event(@other.id, "2026-11-02T00:00:00Z", "open", "other")
    ])
  end

  it "returns exact totals, UTC daily counts and deterministic top names, scoped to the authenticated application" do
    seed_fixture
    get_analytics(range.merge(application_id: @other.id))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "total_events" => 5, "unique_users" => 3,
      "daily" => [ { "date" => "2026-11-01", "events" => 2, "active_users" => 2 },
                   { "date" => "2026-11-02", "events" => 1, "active_users" => 1 },
                   { "date" => "2026-11-03", "events" => 2, "active_users" => 1 } ],
      "top_events" => [ { "name" => "open", "count" => 3 }, { "name" => "purchase", "count" => 2 } ]
    )
    expect(response.headers["Cache-Control"]).to include("no-store")
    get_analytics(range, { "Authorization" => "Bearer #{@other_key}" })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("total_events" => 1, "unique_users" => 1)
  end

  it "applies each filter independently and combines all filters with AND" do
    seed_fixture
    [ [ { name: "open" }, 3, 2 ], [ { platform: "ios" }, 3, 2 ], [ { country: "US" }, 3, 3 ],
      [ { name: "open", platform: "ios", country: "PL" }, 2, 2 ],
      [ { name: "purchase", platform: "web", country: "PL" }, 0, 0 ] ].each do |filters, total, users|
      get_analytics(range.merge(filters))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("total_events" => total, "unique_users" => users)
    end
  end

  it "preserves exact sub-millisecond bounds, zero days and partial UTC days" do
    client.insert_events([
      event(application.id, "2026-11-01T23:59:59.999Z", "excluded", "one"),
      event(application.id, "2026-11-02T00:00:00Z", "included", "one"),
      event(application.id, "2026-11-02T00:00:00.001Z", "excluded", "two")
    ])
    get_analytics(from: "2026-11-02T00:59:59.9991+01:00", to: "2026-11-02T01:00:00.0001+01:00")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "total_events" => 1, "unique_users" => 1,
      "daily" => [ { "date" => "2026-11-01", "events" => 0, "active_users" => 0 },
                   { "date" => "2026-11-02", "events" => 1, "active_users" => 1 } ],
      "top_events" => [ { "name" => "included", "count" => 1 } ]
    )
  end

  it "includes missing days for a completely empty 90-day range and rejects an extra millisecond" do
    get_analytics(from: "2026-01-01T12:00:00Z", to: "2026-04-01T12:00:00Z")
    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data).to include("total_events" => 0, "unique_users" => 0, "top_events" => [])
    expect(data.fetch("daily")).to eq((Date.new(2026, 1, 1)..Date.new(2026, 4, 1)).map do |date|
      { "date" => date.iso8601, "events" => 0, "active_users" => 0 }
    end)
    get_analytics(from: "2026-01-01T12:00:00Z", to: "2026-04-01T12:00:00.001Z")
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "limits top events to ten with alphabetical tie ordering and safely binds malicious names" do
    client.insert_events((1..12).map do |i|
      event(application.id, "2026-11-02T12:00:00Z", format("event_%02d", i), "user")
    end.reverse)
    get_analytics
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("top_events")).to eq((1..10).map do |i|
      { "name" => format("event_%02d", i), "count" => 1 }
    end)
    client.insert_events([ event(application.id, "2026-11-02T12:00:00Z", malicious_name, "user") ])
    get_analytics(range.merge(name: malicious_name))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("total_events" => 1, "top_events" => [ { "name" => malicious_name, "count" => 1 } ])
    get_analytics(range.merge(name: "' OR 1=1 --"))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("total_events" => 0)
  end

  it "rejects missing or invalid authorization before querying ClickHouse" do
    expect(ClickhouseClient).not_to receive(:new)
    get_analytics({}, {})
    expect(response).to have_http_status(:unauthorized)
    get_analytics(range, { "Authorization" => "Bearer #{ApplicationApiKey.generate}" })
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects invalid filters without querying ClickHouse" do
    expect(ClickhouseClient).not_to receive(:new)
    [ {}, range.merge(from: "2026-11-01"), range.merge(to: range[:from]), range.merge(name: [ "open" ]),
      range.merge(platform: "desktop"), range.merge(country: "ZZ"), range.merge(name: " ") ].each do |invalid|
      get_analytics(invalid)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "returns a generic 503 if ClickHouse rejects a query" do
    allow(ClickhouseClient).to receive(:new).and_return(ClickhouseClient.new(password: "synthetic-wrong-password"))
    get_analytics
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("error" => "Service unavailable")
  end
end
