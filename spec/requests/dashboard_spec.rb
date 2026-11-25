require "rails_helper"

RSpec.describe "Local analytics dashboard", type: :request do
  let(:id) { "00000000-0000-4000-8000-000000000001" }
  let(:other_id) { "00000000-0000-4000-8000-000000000002" }
  let(:selection) { { application_id: id, from: "2026-11-01", to: "2026-11-04" } }
  let(:relation) { instance_double(ActiveRecord::Relation) }
  let(:analytics) { instance_double(EventAnalytics) }
  let(:result) do
    { total_events: 2, unique_users: 1,
      daily: [ { date: "2026-11-01", events: 1, active_users: 1 }, { date: "2026-11-02", events: 0, active_users: 0 },
               { date: "2026-11-03", events: 1, active_users: 1 } ], top_events: [ { name: "open", count: 2 } ] }
  end

  before do
    allow(Application).to receive(:order).with(:name, :id).and_return(relation)
    allow(relation).to receive(:pluck).with(:id, :name).and_return([ [ id, "First demo" ], [ other_id, "Second demo" ] ])
    allow(analytics).to receive(:call).and_return(result)
  end

  it "shows labelled controls and an initial state without querying analytics" do
    expect(EventAnalytics).not_to receive(:new)
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    assert_select "h1", text: "Application activity"
    assert_select "#initial-state", text: /Select an application/
    assert_select "form[method=get][action='/']" do
      %w[application_id from to name platform country].each do |field|
        assert_select "label[for='#{field}']", count: 1
        assert_select "[id='#{field}']", count: 1
      end
      assert_select "input[type=date]", count: 2
      assert_select "option[value='#{id}']", text: /First demo/
      assert_select "input[name=api_key]", count: 0
    end
    assert_select "script", count: 0
  end

  it "shows a helpful empty application list" do
    allow(relation).to receive(:pluck).with(:id, :name).and_return([])
    expect(EventAnalytics).not_to receive(:new)
    get "/"
    expect(response).to have_http_status(:ok)
    assert_select "#initial-state", text: /No demo applications/
    assert_select "input[type=submit][disabled]", count: 1
  end

  it "resolves selection, adapts UTC dates and delegates all filters to the shared service" do
    expect(EventAnalytics).to receive(:new).once do |application_id:, filters:|
      expect(application_id).to eq(other_id)
      expect(filters.from).to eq(Time.utc(2026, 11, 1))
      expect(filters.to).to eq(Time.utc(2026, 11, 4))
      expect([ filters.name, filters.platform, filters.country ]).to eq([ "open", "ios", "PL" ])
      analytics
    end
    get "/", params: selection.merge(application_id: other_id, name: "open", platform: "ios", country: "PL")
    expect(response).to have_http_status(:ok)
    assert_select "#total-events", text: "2"
    assert_select "#unique-users", text: "1"
    assert_select "svg[role=img] rect.chart-bar", count: 6
    assert_select "#daily-values tbody tr", count: 3
    assert_select "#top-events tbody tr", count: 1
    assert_select "select#application_id option[selected][value='#{other_id}']", count: 1
  end

  it "maps blank form filters to absent API filters and displays an exact zero result" do
    allow(analytics).to receive(:call).and_return(total_events: 0, unique_users: 0,
      daily: [ { date: "2026-11-01", events: 0, active_users: 0 } ], top_events: [])
    expect(EventAnalytics).to receive(:new).once do |application_id:, filters:|
      expect(application_id).to eq(id)
      expect([ filters.name, filters.platform, filters.country ]).to eq([ nil, nil, nil ])
      analytics
    end
    get "/", params: selection.merge(to: "2026-11-02", name: "", platform: "", country: "")
    expect(response).to have_http_status(:ok)
    assert_select "#empty-state", text: /No matching events/
    assert_select "#total-events", text: "0"
    assert_select "#unique-users", text: "0"
    assert_select "#daily-values tbody td", text: "0", count: 2
    assert_select "#top-events", count: 0
  end

  it "rejects invalid selections and filters without querying analytics" do
    expect(EventAnalytics).not_to receive(:new)
    [ { application_id: "not-an-id" }, { application_id: [ id ] }, { application_id: "" }, { from: "2026-02-30" },
      { from: [ "2026-11-01" ] }, { to: "2026-11-01" }, { to: "2027-11-01" }, { name: [ "open" ] },
      { name: " " }, { platform: "desktop" }, { country: "ZZ" } ].each do |invalid|
      get "/", params: selection.merge(invalid)
      expect(response).to have_http_status(:unprocessable_entity)
      assert_select "[role=alert]", count: 1
      assert_select "#total-events", count: 0
    end
  end

  it "renders escaped event and application names without executable markup" do
    malicious = "<script>alert(1)</script>"
    allow(relation).to receive(:pluck).with(:id, :name).and_return([ [ id, malicious ] ])
    allow(analytics).to receive(:call).and_return(result.merge(top_events: [ { name: malicious, count: 2 } ]))
    allow(EventAnalytics).to receive(:new).and_return(analytics)
    get "/", params: selection.merge(name: malicious)
    expect(response).to have_http_status(:ok)
    assert_select "script", count: 0
    assert_select "#top-events tbody th", text: malicious
    expect(response.body).not_to include(malicious)
  end

  it "shows a generic dependency error rather than stale or partial counters" do
    allow(EventAnalytics).to receive(:new).and_return(analytics)
    allow(analytics).to receive(:call).and_raise(ClickhouseClient::Unavailable, "private-clickhouse-detail")
    get "/", params: selection
    expect(response).to have_http_status(:service_unavailable)
    assert_select "[role=alert]", text: /Analytics unavailable/
    assert_select "#total-events", count: 0
    expect(response.body).not_to include("private-clickhouse-detail")
    allow(Application).to receive(:order).and_raise(ActiveRecord::ConnectionNotEstablished, "private-pg-detail")
    get "/"
    expect(response).to have_http_status(:service_unavailable)
    assert_select "[role=alert]", text: /Analytics unavailable/
    expect(response.body).not_to include("private-pg-detail")
  end

  it "rejects non-local peers without querying databases" do
    expect(Application).not_to receive(:order)
    get "/", env: { "REMOTE_ADDR" => "192.0.2.10" }
    expect(response).to have_http_status(:not_found)
  end
end
