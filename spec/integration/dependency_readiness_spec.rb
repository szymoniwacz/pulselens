require "rails_helper"

RSpec.describe "Real service readiness", :integration, type: :request do
  it "executes a PostgreSQL query and an authenticated ClickHouse query" do
    get "/ready"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => "ready", "checks" => { "postgresql" => "ok", "clickhouse" => "ok" })
  end

  it "boots the application and its view/assets stack without domain features" do
    expect(Rails.application.config.time_zone).to eq("UTC")
    expect(ApplicationController.superclass).to eq(ActionController::Base)
    expect(ApplicationRecord.abstract_class?).to be(true)
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
