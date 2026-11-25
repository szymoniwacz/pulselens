require "rails_helper"

RSpec.describe "Operational endpoints", type: :request do
  it "serves process liveness without checking dependencies" do
    expect(DependencyReadiness).not_to receive(:new)
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "reports ready only when both stores are available" do
    probe = instance_double(DependencyReadiness, call: { postgresql: "ok", clickhouse: "ok" })
    allow(DependencyReadiness).to receive(:new).and_return(probe)
    get "/ready"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => "ready", "checks" => { "postgresql" => "ok", "clickhouse" => "ok" })
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  %i[postgresql clickhouse].each do |dependency|
    it "returns 503 when #{dependency} is unavailable" do
      checks = { postgresql: "ok", clickhouse: "ok" }.merge(dependency => "unavailable")
      allow(DependencyReadiness).to receive(:new).and_return(instance_double(DependencyReadiness, call: checks))
      get "/ready"
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["status"]).to eq("not_ready")
      expect(response.parsed_body["checks"][dependency.to_s]).to eq("unavailable")
    end
  end
end
