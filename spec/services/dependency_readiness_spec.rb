require "rails_helper"
require "socket"
require_relative "../support/stalling_http_peer"

RSpec.describe DependencyReadiness do
  subject(:checks) { described_class.new.call }

  let(:connection) { instance_double(PG::Connection) }
  let(:result) { instance_double(PG::Result, getvalue: "1") }
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
    allow(PG::Connection).to receive(:connect_start).and_return(connection)
    allow(connection).to receive(:connect_poll).and_return(PG::PGRES_POLLING_OK)
    allow(connection).to receive(:setnonblocking).with(true)
    allow(connection).to receive(:exec).with("SELECT 1").and_yield(result)
    allow(connection).to receive(:finished?).and_return(false)
    allow(connection).to receive(:finish)
    allow(Net::HTTP).to receive(:new).with("127.0.0.1", 8123, nil).and_return(http)
    allow(http).to receive(:use_ssl=).with(false)
    %i[open_timeout= read_timeout= write_timeout=].each { |setting| allow(http).to receive(setting).with(2) }
    allow(http).to receive(:max_retries=).with(0)
    allow(http_response).to receive(:body).and_return("1\n")
    allow(http).to receive(:request).and_return(http_response)
  end

  it "checks both databases with a harmless query" do
    expect(checks).to eq(postgresql: "ok", clickhouse: "ok")
    expect(connection).to have_received(:finish).once
    expect(PG::Connection).to have_received(:connect_start).with(hash_including(hostaddr: "127.0.0.1"))
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
    allow(connection).to receive(:exec).and_raise(PG::ConnectionBad, "fixture_secret at sensitive-url")
    allow(Rails.logger).to receive(:warn)
    expect(checks).to eq(postgresql: "unavailable", clickhouse: "ok")
    expect(Rails.logger).to have_received(:warn).with("PostgreSQL readiness failed (PG::ConnectionBad)")
    expect(connection).to have_received(:finish).once
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

  it "interrupts stalled PostgreSQL I/O, closes its socket and leaves the application pool untouched" do
    reader, writer = Socket.pair(:UNIX, :STREAM, 0)
    stub_const("DependencyReadiness::PROBE_TIMEOUT", 0.05)
    expect(ActiveRecord::Base.connection_pool).not_to receive(:with_connection)
    allow(connection).to receive(:exec) { reader.read(1) }
    allow(Rails.logger).to receive(:warn)

    expect(Timeout.timeout(3) { checks }).to eq(postgresql: "unavailable", clickhouse: "ok")
    expect(connection).to have_received(:finish).once
    expect(http).to have_received(:request).once
    expect(Rails.logger).to have_received(:warn).with("PostgreSQL readiness failed (Timeout::Error)")
  ensure
    reader&.close
    writer&.close
  end

  it "closes an unsuccessful initial PostgreSQL connection" do
    allow(connection).to receive(:connect_poll).and_return(PG::PGRES_POLLING_FAILED)
    expect(connection).not_to receive(:exec)
    expect(checks).to eq(postgresql: "unavailable", clickhouse: "ok")
    expect(connection).to have_received(:finish).once
  end

  it "bounds PostgreSQL name resolution before creating a physical connection" do
    reader, writer = Socket.pair(:UNIX, :STREAM, 0)
    stub_const("DependencyReadiness::PROBE_TIMEOUT", 0.05)
    allow(Resolv).to receive(:getaddress) { reader.read(1) }
    expect(PG::Connection).not_to receive(:connect_start)

    expect(Timeout.timeout(3) { checks }).to eq(postgresql: "unavailable", clickhouse: "ok")
  ensure
    reader&.close
    writer&.close
  end

  it "bounds a continuously arriving ClickHouse response and closes its socket before the next probe" do
    stub_const("DependencyReadiness::PROBE_TIMEOUT", 0.25)
    peer = StallingHttpPeer.new
    ENV["CLICKHOUSE_URL"] = "http://127.0.0.1:#{peer.port}"
    allow(Net::HTTP).to receive(:new).and_call_original
    allow(Rails.logger).to receive(:warn)

    expect(Timeout.timeout(3) { checks }).to eq(postgresql: "ok", clickhouse: "unavailable")
    expect(Timeout.timeout(3) { peer.closed.pop }).to eq(true)
    expect(peer.requests).to eq(1)
    expect(Rails.logger).to have_received(:warn).with("ClickHouse readiness failed (Timeout::Error)")

    peer.respond_normally!
    expect(described_class.new.call).to eq(postgresql: "ok", clickhouse: "ok")
    expect(peer.requests).to eq(2)
  ensure
    peer&.close
  end
end
