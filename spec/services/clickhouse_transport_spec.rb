require "rails_helper"
require_relative "../support/stalling_http_peer"

RSpec.describe "ClickHouse event transport" do
  it "bounds a continuously arriving response, closes the socket and never retries the write" do
    stub_const("ClickhouseClient::INSERT_TIMEOUT", 0.25)
    peer = StallingHttpPeer.new
    client = ClickhouseClient.new(url: "http://127.0.0.1:#{peer.port}")
    row = {
      application_id: "00000000-0000-0000-0000-000000000001",
      event_id: "00000000-0000-0000-0000-000000000002",
      name: "app_open", user_id: "synthetic", occurred_at: Time.utc(2026, 11, 25),
      received_at: Time.utc(2026, 11, 25), platform: "ios", country: "PL", properties: {}
    }

    expect { Timeout.timeout(3) { client.insert_events([ row ]) } }.to raise_error(ClickhouseClient::Unavailable)
    expect(Timeout.timeout(3) { peer.closed.pop }).to be(true)
    expect(peer.requests).to eq(1)
  ensure
    peer&.close
  end
end
