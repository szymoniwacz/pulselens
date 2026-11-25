require "rails_helper"
require "securerandom"
require "stringio"

RSpec.describe "Real event ingestion", :integration, type: :request do
  let(:client) { ClickhouseClient.new }
  let(:event) do
    { "event_id" => SecureRandom.uuid, "name" => "app_open", "user_id" => "synthetic-user", "occurred_at" => "2026-11-02T00:30:00.456789+01:00" }
  end

  def submit(key, events)
    post "/api/v1/events", params: JSON.generate(events: events), headers: { "Authorization" => "Bearer #{key}", "Content-Type" => "application/json" }
  end

  def stored(id)
    client.query(<<~SQL, bindings: { application: id })
      SELECT application_id, event_id, name, user_id, occurred_at, received_at, platform, country, properties
      FROM events WHERE application_id = {application:UUID} ORDER BY event_id
    SQL
  end

  it "stores normalized server-scoped events for two applications and does not deduplicate" do
    first, first_key = Application.issue_key!(name: "Ingestion first")
    second, second_key = Application.issue_key!(name: "Ingestion second")
    explicit = event.merge("platform" => "android", "country" => "PL", "properties" => { "nested" => [ 1, true, "ż" ] })
    submit(first_key, [ event, explicit.merge("event_id" => SecureRandom.uuid) ])
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq("accepted" => 2)
    rows = stored(first.id)
    expect(rows.length).to eq(2)
    expect(rows.map { |row| row.fetch("application_id") }.uniq).to eq([ first.id ])
    expect(rows.map { |row| row.fetch("occurred_at") }.uniq).to eq([ "2026-11-01 23:30:00.456" ])
    expect(rows.map { |row| row.fetch("received_at") }.uniq.length).to eq(1)
    expect(rows.find { |row| row["event_id"] == event["event_id"] }).to include("platform" => "unknown", "country" => "unknown", "properties" => "{}")
    expect(JSON.parse(rows.find { |row| row["platform"] == "android" }.fetch("properties"))).to eq(explicit.fetch("properties"))
    expect(stored(second.id)).to be_empty
    submit(second_key, [ explicit ])
    expect(response).to have_http_status(:created)
    expect(stored(second.id).length).to eq(1)
    expect(stored(first.id).length).to eq(2)
    submit(first_key, [ event ])
    expect(response).to have_http_status(:created)
    expect(stored(first.id).length).to eq(3)
  end

  it "writes nothing when a later event is invalid or attempts to override server fields" do
    first, key = Application.issue_key!(name: "Rejected ingestion")
    second, = Application.issue_key!(name: "Isolation target")
    [ { "name" => nil }, { "application_id" => second.id }, { "received_at" => nil } ].each do |invalid|
      submit(key, [ event, event.merge(invalid) ])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("index" => 1)
    end
    expect(stored(first.id)).to be_empty
    expect(stored(second.id)).to be_empty
  end

  it "does not log the bearer key, digest, or malformed raw body" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    loggers = [ Rails.logger, ActionController::Base.logger, ActiveRecord::Base.logger ].compact.uniq
    loggers.each { |sink| sink.broadcast_to(logger) }
    application, key = Application.issue_key!(name: "Ingestion log redaction")
    submit(key, [ event ])
    expect(response).to have_http_status(:created)
    post "/api/v1/events", params: "{malformed-#{key}", headers: { "Authorization" => "Bearer #{key}", "Content-Type" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(output.string).to include("Processing by Api::V1::EventsController#create")
    expect(output.string).not_to include(key, application.api_key_digest, "{malformed-")
  ensure
    loggers&.each { |sink| sink.stop_broadcasting_to(logger) }
  end
end
