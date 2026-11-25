require "rails_helper"
require "securerandom"

RSpec.describe "Event ingestion request", type: :request do
  let(:key) { ApplicationApiKey.generate }
  let(:application_id) { SecureRandom.uuid }
  let(:client) { instance_double(ClickhouseClient) }
  let(:headers) { { "Authorization" => "Bearer #{key}", "Content-Type" => "application/json" } }
  let(:event) do
    { "event_id" => SecureRandom.uuid, "name" => "open", "user_id" => "synthetic-user", "occurred_at" => "2026-11-01T00:00:00Z" }
  end

  before do
    allow(Application).to receive(:authenticate_bearer).and_return(nil)
    allow(Application).to receive(:authenticate_bearer).with("Bearer #{key}").and_return(Struct.new(:id).new(application_id))
    allow(ClickhouseClient).to receive(:new).and_return(client)
  end

  def submit(payload, request_headers = headers)
    post "/api/v1/events", params: payload, headers: request_headers
  end

  it "confirms the entire valid batch with exactly one insert" do
    expect(client).to receive(:insert_events).once do |rows|
      expect(rows.length).to eq(1000)
      expect(rows.map { |row| row.fetch(:application_id) }.uniq).to eq([ application_id ])
      expect(rows.map { |row| row.fetch(:received_at) }.uniq.length).to eq(1)
      true
    end
    submit(JSON.generate(events: Array.new(1000, event)))
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq("accepted" => 1000)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "does not invoke storage for invalid batches and reports a zero-based event index" do
    expect(ClickhouseClient).not_to receive(:new)
    submit(JSON.generate(events: [ event, event.merge("application_id" => SecureRandom.uuid) ]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("error" => "Invalid event batch", "field" => "application_id", "index" => 1)
    [ [], Array.new(1001, event) ].each do |events|
      submit(JSON.generate(events: events))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("field" => "events", "index" => nil)
    end
  end

  it "rejects malformed JSON and wrong JSON types with distinct statuses" do
    expect(ClickhouseClient).not_to receive(:new)
    [ "{broken", "", "{\"name\":\"\xff\"}".b ].each do |body|
      submit(body)
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "Malformed JSON")
    end
    [ "null", "[]", "true", '{"events":[null]}' ].each do |body|
      submit(body)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "checks authorization before parsing a within-limit body or writing" do
    expect(ClickhouseClient).not_to receive(:new)
    [ nil, "Bearer invalid" ].each do |authorization|
      request_headers = { "Content-Type" => "application/json" }
      request_headers["Authorization"] = authorization if authorization
      submit("{broken", request_headers)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "accepts an exact two-MiB body and rejects one extra byte before storage" do
    valid = JSON.generate(events: [ event ])
    boundary = valid.ljust(IngestionBody::MAX_BYTES, " ")
    expect(client).to receive(:insert_events).once.and_return(true)
    submit(boundary)
    expect(response).to have_http_status(:created)
    submit(boundary + " ")
    expect(response).to have_http_status(413)
    expect(response.parsed_body).to eq("error" => "Request body too large")
  end

  it "returns only a generic 503 after one failed insert, without retrying" do
    expect(client).to receive(:insert_events).once.and_raise(ClickhouseClient::Unavailable, "private-detail")
    submit(JSON.generate(events: [ event ]))
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("error" => "Service unavailable")
  end

  it "does not report 201 if the client does not confirm the insert" do
    expect(client).to receive(:insert_events).once.and_return(false)
    submit(JSON.generate(events: [ event ]))
    expect(response).to have_http_status(:service_unavailable)
  end
end
