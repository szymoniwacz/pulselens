require "rails_helper"

RSpec.describe DependencyReadiness do
  subject(:checks) { described_class.new.call }

  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }
  let(:http) { instance_double(Net::HTTP) }
  let(:http_response) { Net::HTTPOK.new("1.1", "200", "OK") }

  around do |example|
    names = %w[CLICKHOUSE_URL CLICKHOUSE_USER CLICKHOUSE_PASSWORD]
    original = ENV.to_h.slice(*names)
    ENV["CLICKHOUSE_URL"] = "http://127.0.0.1:8123"
    ENV["CLICKHOUSE_USER"] = "fixture_user"
    ENV["CLICKHOUSE_PASSWORD"] = "fixture_secret"
    example.run
  ensure
    names.each { |name| original.key?(name) ? ENV[name] = original[name] : ENV.delete(name) }
  end

  before do
    allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_yield(connection)
    allow(connection).to receive(:select_value).with("SELECT 1").and_return(1)
    allow(Net::HTTP).to receive(:new).with("127.0.0.1", 8123, nil).and_return(http)
    allow(http).to receive(:use_ssl=).with(false)
    %i[open_timeout= read_timeout= write_timeout=].each { |setting| allow(http).to receive(setting).with(2) }
    allow(http).to receive(:max_retries=).with(0)
    allow(http_response).to receive(:body).and_return("1\n")
    allow(http).to receive(:request).and_return(http_response)
  end

  it "checks both databases with a harmless query" do
    expect(checks).to eq(postgresql: "ok", clickhouse: "ok")
    expect(http).to have_received(:request) do |request|
      expect(request).to be_a(Net::HTTP::Post)
      expect(request.path).to eq("/")
      expect(request.body).to eq("SELECT 1 FORMAT TabSeparated")
      expect(request["Authorization"]).to eq("Basic #{Base64.strict_encode64('fixture_user:fixture_secret')}")
    end
  end

  it "sets finite HTTP deadlines and disables implicit retries" do
    checks
    %i[open_timeout= read_timeout= write_timeout=].each { |setting| expect(http).to have_received(setting).with(2) }
    expect(http).to have_received(:max_retries=).with(0)
  end

  it "still checks ClickHouse when PostgreSQL raises, without leaking the exception message" do
    allow(connection).to receive(:select_value).and_raise(PG::ConnectionBad, "fixture_secret at sensitive-url")
    allow(Rails.logger).to receive(:warn)
    expect(checks).to eq(postgresql: "unavailable", clickhouse: "ok")
    expect(Rails.logger).to have_received(:warn).with("PostgreSQL readiness failed (PG::ConnectionBad)")
  end

  [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED ].each do |error|
    it "reports #{error} as unavailable without retrying or leaking details" do
      allow(http).to receive(:request).and_raise(error, "fixture_secret")
      expect(checks).to eq(postgresql: "ok", clickhouse: "unavailable")
      expect(http).to have_received(:request).once
    end
  end

  it "rejects an unsuccessful ClickHouse response" do
    allow(http).to receive(:request).and_return(Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized"))
    expect(checks[:clickhouse]).to eq("unavailable")
  end

  it "does not treat an arbitrary 200 response as database readiness" do
    allow(http_response).to receive(:body).and_return("not a query result")
    expect(checks[:clickhouse]).to eq("unavailable")
  end

  it "rejects URL credentials so errors cannot echo embedded secrets" do
    ENV["CLICKHOUSE_URL"] = "http://user:fixture_secret@127.0.0.1:8123"
    expect(http).not_to receive(:request)
    expect(checks[:clickhouse]).to eq("unavailable")
  end
end
