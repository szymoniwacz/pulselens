require "rails_helper"
require "open3"
require "securerandom"

RSpec.describe "Cross-system analytics journey", :integration, type: :request do
  let(:client) { ClickhouseClient.new }
  let(:range) { { from: "2026-11-01T00:00:00Z", to: "2026-11-04T00:00:00Z" } }
  let(:dates) { { from: "2026-11-01", to: "2026-11-04" } }

  def create_demo
    name = "Journey #{SecureRandom.uuid}"
    output, _stderr, status = Open3.capture3({ "RAILS_ENV" => "test", "APPLICATION_NAME" => name }, "bin/rails", "applications:create")
    # Do not include subprocess output (which contains a one-time key) in failure diagnostics.
    expect(status.success?).to be(true), "applications:create failed"
    match = /\AApplication ID: ([0-9a-f-]{36})\nAPI key \(shown once\): ([0-9a-f]{64})\n\z/.match(output)
    expect(!match.nil?).to be(true), "Unexpected applications:create output"
    application = Application.find_by!(id: match[1], name: name)
    expect(application.api_key_digest == ApplicationApiKey.digest(match[2])).to be(true)
    [ application, match[2] ]
  end

  def event(timestamp, name, user, platform = "ios", country = "PL")
    { event_id: SecureRandom.uuid, occurred_at: timestamp, name: name, user_id: user, platform: platform, country: country }
  end

  def submit(events, key: nil, payload: nil)
    headers = { "Content-Type" => "application/json" }
    headers["Authorization"] = "Bearer #{key}" if key
    post "/api/v1/events", params: payload || JSON.generate(events: events), headers: headers
  end

  def stored(id)
    client.query(<<~SQL, bindings: { application: id })
      SELECT event_id, occurred_at FROM events
      WHERE application_id = {application:UUID} ORDER BY event_id
    SQL
  end

  def expected(total, unique, daily_counts, top)
    { "total_events" => total, "unique_users" => unique,
      "daily" => daily_counts.each_with_index.map { |(events, users), index| { "date" => (Date.new(2026, 11, 1) + index).iso8601, "events" => events, "active_users" => users } },
      "top_events" => top.map { |name, count| { "name" => name, "count" => count } } }
  end

  def assert_surfaces(application, key, result, filters: {}, credentials: [])
    get "/api/v1/analytics", params: range.merge(filters), headers: { "Authorization" => "Bearer #{key}" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(result)

    get "/", params: dates.merge(filters).merge(application_id: application.id)
    expect(response).to have_http_status(:ok)
    # Check secrets before assertions that may print rendered HTML on failure.
    expect(credentials.any? { |secret| response.body.include?(secret) }).to be(false), "Dashboard exposed a credential"
    assert_select "#total-events", text: result.fetch("total_events").to_s
    assert_select "#unique-users", text: result.fetch("unique_users").to_s
    assert_select "#daily-values tbody tr", count: result.fetch("daily").length do |rows|
      expect(rows.map { |row| row.css("th, td").map(&:text) }).to eq(result.fetch("daily").map { |day| [ day.fetch("date"), day.fetch("events").to_s, day.fetch("active_users").to_s ] })
    end
    if result.fetch("top_events").empty?
      assert_select "#empty-state", count: 1
      assert_select "#top-events", count: 0
    else
      assert_select "#top-events tbody tr", count: result.fetch("top_events").length do |rows|
        expect(rows.map { |row| row.css("th, td").map(&:text) }).to eq(result.fetch("top_events").map { |entry| [ entry.fetch("name"), entry.fetch("count").to_s ] })
      end
    end
  end

  it "creates applications through the operator command and reads only events inserted through the HTTP endpoint" do
    first, first_key = create_demo
    second, second_key = create_demo
    credentials = [ first_key, second_key, first.api_key_digest, second.api_key_digest ]
    first_events = [
      event("2026-10-31T23:59:59.999Z", "outside", "outside"),
      event("2026-11-01T00:00:00Z", "open", "returning"),
      event("2026-11-02T00:30:00+01:00", "purchase", "new", "web", "US"),
      event("2026-11-03T12:00:00Z", "open", "returning"),
      event("2026-11-03T23:59:59.999Z", "open", "third", "android"),
      event("2026-11-04T00:00:00Z", "outside", "outside")
    ]
    second_events = [ event("2026-11-01T12:00:00Z", "open", "returning"),
                      event("2026-11-03T12:00:00Z", "purchase", "returning", "web", "US") ]
    submit(first_events, key: first_key)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq("accepted" => 6)
    submit(second_events, key: second_key)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq("accepted" => 2)

    first_rows = stored(first.id)
    expect(first_rows.map { |row| row.fetch("event_id") }).to match_array(first_events.map { |entry| entry.fetch(:event_id) })
    expect(first_rows.find { |row| row.fetch("event_id") == first_events[2].fetch(:event_id) }).to include("occurred_at" => "2026-11-01 23:30:00.000")
    expect(stored(second.id).map { |row| row.fetch("event_id") }).to match_array(second_events.map { |entry| entry.fetch(:event_id) })

    assert_surfaces(first, first_key, expected(4, 3, [ [ 2, 2 ], [ 0, 0 ], [ 2, 2 ] ], [ [ "open", 3 ], [ "purchase", 1 ] ]), credentials: credentials)
    assert_surfaces(second, second_key, expected(2, 1, [ [ 1, 1 ], [ 0, 0 ], [ 1, 1 ] ], [ [ "open", 1 ], [ "purchase", 1 ] ]), credentials: credentials)
    assert_surfaces(first, first_key, expected(2, 1, [ [ 1, 1 ], [ 0, 0 ], [ 1, 1 ] ], [ [ "open", 2 ] ]),
      filters: { name: "open", platform: "ios", country: "PL" }, credentials: credentials)
    assert_surfaces(first, first_key, expected(0, 0, [ [ 0, 0 ], [ 0, 0 ], [ 0, 0 ] ], []),
      filters: { name: "purchase", platform: "ios" }, credentials: credentials)
  end

  it "leaves stored rows unchanged after rejected batches, unknown credentials and excessive input" do
    application, key = Application.issue_key!(name: "Journey rejection #{SecureRandom.uuid}")
    other, = Application.issue_key!(name: "Journey isolation #{SecureRandom.uuid}")
    accepted = event("2026-11-01T00:00:00Z", "open", "one")
    rejected = event("2026-11-03T00:00:00Z", "open", "two")
    submit([ accepted ], key: key)
    expect(response).to have_http_status(:created)
    before = stored(application.id)
    expect(before.length).to eq(1)

    [ nil, ApplicationApiKey.generate, "invalid" ].each do |invalid_key|
      submit([ rejected ], key: invalid_key)
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "Unauthorized")
      get "/api/v1/analytics", params: range, headers: invalid_key ? { "Authorization" => "Bearer #{invalid_key}" } : {}
      expect(response).to have_http_status(:unauthorized)
    end
    submit([ rejected, rejected.merge(application_id: other.id) ], key: key)
    expect(response).to have_http_status(422)
    expect(response.parsed_body).to include("field" => "application_id", "index" => 1)
    submit([ rejected, rejected.merge(name: nil) ], key: key)
    expect(response).to have_http_status(422)
    expect(response.parsed_body).to include("field" => "name", "index" => 1)
    submit(Array.new(1001, rejected), key: key)
    expect(response).to have_http_status(422)
    submit(nil, key: key, payload: "{broken")
    expect(response).to have_http_status(:bad_request)
    submit(nil, key: key, payload: JSON.generate(events: [ rejected ]).ljust(IngestionBody::MAX_BYTES + 1, " "))
    expect(response).to have_http_status(413)
    expect(stored(application.id)).to eq(before)
    expect(stored(other.id)).to be_empty
    assert_surfaces(application, key, expected(1, 1, [ [ 1, 1 ], [ 0, 0 ], [ 0, 0 ] ], [ [ "open", 1 ] ]),
      credentials: [ key, application.api_key_digest ])
  end
end
