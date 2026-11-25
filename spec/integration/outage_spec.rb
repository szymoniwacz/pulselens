require "rails_helper"
require "securerandom"

RSpec.describe "Real dependency outage", :outage, type: :request do
  it "keeps liveness healthy while reporting the stopped dependency as unavailable" do
    dependency = ENV.fetch("EXPECT_UNAVAILABLE")
    expect(%w[postgresql clickhouse]).to include(dependency)
    get "/up"
    expect(response).to have_http_status(:ok)
    get "/ready"
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["checks"][dependency]).to eq("unavailable")
    other = dependency == "postgresql" ? "clickhouse" : "postgresql"
    expect(response.parsed_body["checks"][other]).to eq("ok")
  end

  def outage_event
    { event_id: SecureRandom.uuid, name: "open", user_id: "synthetic-user", occurred_at: "2026-11-01T00:00:00Z" }
  end

  def assert_api_unavailable
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("error" => "Service unavailable")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  def assert_dashboard_unavailable
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Cache-Control"]).to include("no-store")
    assert_select "[role=alert]", text: /Analytics unavailable/
    assert_select "#total-events", count: 0
    assert_select "#unique-users", count: 0
  end

  if ENV["EXPECT_UNAVAILABLE"] == "postgresql"
    it "fails real ingestion, analytics and dashboard requests when PostgreSQL is stopped" do
      key = ApplicationApiKey.generate
      headers = { "Authorization" => "Bearer #{key}", "Content-Type" => "application/json" }
      post "/api/v1/events", params: JSON.generate(events: [ outage_event ]), headers: headers
      assert_api_unavailable
      get "/api/v1/analytics", params: { from: "2026-11-01T00:00:00Z", to: "2026-11-02T00:00:00Z" }, headers: headers
      assert_api_unavailable
      get "/"
      assert_dashboard_unavailable
    end
  end

  if ENV["EXPECT_UNAVAILABLE"] == "clickhouse"
    it "returns a generic analytics 503 with valid authentication when ClickHouse is stopped" do
      _, key = Application.issue_key!(name: "Analytics outage")
      get "/api/v1/analytics", params: { from: "2026-11-01T00:00:00Z", to: "2026-11-02T00:00:00Z" },
          headers: { "Authorization" => "Bearer #{key}" }
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq("error" => "Service unavailable")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "returns 503 for valid HTTP ingestion and selected dashboard when ClickHouse is stopped" do
      application, key = Application.issue_key!(name: "Journey outage #{SecureRandom.uuid}")
      post "/api/v1/events", params: JSON.generate(events: [ outage_event ]),
          headers: { "Authorization" => "Bearer #{key}", "Content-Type" => "application/json" }
      assert_api_unavailable
      get "/", params: { application_id: application.id, from: "2026-11-01", to: "2026-11-02" }
      expect(response.body.include?(key) || response.body.include?(application.api_key_digest)).to be(false)
      assert_dashboard_unavailable
    end

    it "fails the event client safely while ClickHouse is stopped" do
      expect { ClickhouseClient.new.query("SELECT 1") }.to raise_error(
        ClickhouseClient::Unavailable, "ClickHouse unavailable or operation timed out"
      ) do |error|
        expect(error.cause).to be_nil
      end
    end
  end
end
