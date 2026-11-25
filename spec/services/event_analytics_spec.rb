require "rails_helper"

RSpec.describe EventAnalytics do
  let(:client) { instance_double(ClickhouseClient) }
  let(:application_id) { SecureRandom.uuid }
  let(:filters) { AnalyticsFilters.new(from: "2026-11-01T00:00:00Z", to: "2026-11-03T00:00:00Z", name: "x' OR 1=1 --", platform: "ios", country: "PL") }

  it "binds application and all filters on every query and fills missing days" do
    expected_bindings = { application: application_id, from: "2026-11-01 00:00:00.000", to: "2026-11-03 00:00:00.000",
                          name: filters.name, platform: "ios", country: "PL" }
    responses = [ [ { "total_events" => "2", "unique_users" => "1" } ],
                  [ { "day" => "2026-11-01", "events" => "2", "active_users" => "1" } ],
                  [ { "name" => filters.name, "event_count" => "2" } ] ]
    expect(client).to receive(:query).exactly(3).times do |sql, bindings:|
      expect(sql).to include("application_id = {application:UUID}", "occurred_at >= {from:DateTime64(3, 'UTC')}",
                             "occurred_at < {to:DateTime64(3, 'UTC')}", "name = {name:String}", "platform = {platform:String}", "country = {country:String}")
      expect(sql).not_to include(filters.name, application_id)
      expect(bindings).to eq(expected_bindings)
      responses.shift
    end
    expect(described_class.new(application_id: application_id, filters: filters, client: client).call).to eq(
      total_events: 2, unique_users: 1,
      daily: [ { date: "2026-11-01", events: 2, active_users: 1 }, { date: "2026-11-02", events: 0, active_users: 0 } ],
      top_events: [ { name: filters.name, count: 2 } ]
    )
  end

  it "fails safely if the totals response has no row" do
    allow(client).to receive(:query).and_return([])
    expect { described_class.new(application_id: application_id, filters: filters, client: client).call }.to raise_error(ClickhouseClient::Unavailable)
  end
end
