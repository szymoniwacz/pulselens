require "rails_helper"
require "securerandom"

RSpec.describe "Dashboard and API parity", :integration, type: :request do
  let(:client) { ClickhouseClient.new }
  let(:range) { { from: "2026-11-01", to: "2026-11-04" } }

  def event(application_id, date, name, user, platform, country)
    { application_id: application_id, event_id: SecureRandom.uuid, name: name, user_id: user,
      occurred_at: Time.iso8601(date), received_at: Time.utc(2026, 11, 25), platform: platform, country: country, properties: {} }
  end

  def assert_parity(application, key, filters = {})
    get "/api/v1/analytics", params: { from: "2026-11-01T00:00:00Z", to: "2026-11-04T00:00:00Z" }.merge(filters),
        headers: { "Authorization" => "Bearer #{key}" }
    expect(response).to have_http_status(:ok)
    expected = response.parsed_body
    get "/", params: range.merge(application_id: application.id).merge(filters)
    expect(response).to have_http_status(:ok)
    assert_select "#total-events", text: expected.fetch("total_events").to_s
    assert_select "#unique-users", text: expected.fetch("unique_users").to_s
    assert_select "#daily-values tbody tr", count: expected.fetch("daily").length do |rows|
      actual = rows.map { |row| row.css("th, td").map(&:text) }
      expect(actual).to eq(expected.fetch("daily").map { |day| [ day.fetch("date"), day.fetch("events").to_s, day.fetch("active_users").to_s ] })
    end
    if expected.fetch("top_events").empty?
      assert_select "#empty-state", count: 1
    else
      assert_select "#top-events tbody tr", count: expected.fetch("top_events").length do |rows|
        expect(rows.map { |row| row.css("th, td").map(&:text) }).to eq(expected.fetch("top_events").map { |entry| [ entry.fetch("name"), entry.fetch("count").to_s ] })
      end
    end
    expect(response.body).not_to include(key, application.api_key_digest)
    assert_select "script", count: 0
    expected
  end

  it "shows the same exact results as the API for two applications and each combined filter" do
    first, first_key = Application.issue_key!(name: "Dashboard first")
    second, second_key = Application.issue_key!(name: "Dashboard second")
    client.insert_events([
      event(first.id, "2026-11-01T00:00:00Z", "open", "returning", "ios", "PL"),
      event(first.id, "2026-11-03T12:00:00Z", "open", "returning", "ios", "PL"),
      event(first.id, "2026-11-03T13:00:00Z", "purchase", "new", "web", "US"),
      event(first.id, "2026-11-04T00:00:00Z", "outside", "new", "ios", "PL"),
      event(second.id, "2026-11-01T00:00:00Z", "other", "other", "android", "DE")
    ])
    expect(assert_parity(first, first_key)).to include("total_events" => 3, "unique_users" => 2)
    expect(response.body).not_to include(second_key, second.api_key_digest)
    [ { name: "open" }, { platform: "ios" }, { country: "PL" }, { name: "open", platform: "ios", country: "PL" } ].each do |filters|
      expect(assert_parity(first, first_key, filters)).to include("total_events" => 2, "unique_users" => 1)
    end
    expect(assert_parity(first, first_key, { name: "purchase", platform: "ios" })).to include("total_events" => 0, "unique_users" => 0)
    expect(assert_parity(second, second_key)).to include("total_events" => 1, "unique_users" => 1)
    expect(response.body).not_to include(first_key, first.api_key_digest)
  end
end
