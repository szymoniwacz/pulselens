require "rails_helper"

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

  if ENV["EXPECT_UNAVAILABLE"] == "postgresql"
    it "cannot authenticate when PostgreSQL is stopped" do
      header = "Bearer #{ApplicationApiKey.generate}"
      expect { Application.authenticate_bearer(header) }.to raise_error(ActiveRecord::ActiveRecordError)
    end
  end

  if ENV["EXPECT_UNAVAILABLE"] == "clickhouse"
    it "fails the event client safely while ClickHouse is stopped" do
      expect { ClickhouseClient.new.query("SELECT 1") }.to raise_error(
        ClickhouseClient::Unavailable, "ClickHouse unavailable or operation timed out"
      ) do |error|
        expect(error.cause).to be_nil
      end
    end
  end
end
