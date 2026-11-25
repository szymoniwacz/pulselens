require "rails_helper"
require "stringio"

RSpec.describe "Application API authentication", :integration, type: :request do
  before do
    stub_const("AuthenticationProbeController", Class.new(Api::BaseController) do
      def show
        render json: { application_id: current_application.id }
      end
    end)
    Rails.application.routes.draw do
      get "/__auth_probe", to: "authentication_probe#show"
    end
  end

  after do
    Rails.application.reload_routes!
  end

  it "persists only a digest and resolves each of two applications separately" do
    first, first_key = Application.issue_key!(name: "Synthetic first")
    second, second_key = Application.issue_key!(name: "Synthetic second")
    expect(first.id).to match(/\A[0-9a-f-]{36}\z/)
    expect(first_key).not_to eq(second_key)
    expect(first.reload.api_key_digest).to eq(Digest::SHA256.hexdigest(first_key))
    expect(first.attributes.values).not_to include(first_key)
    expect(first.inspect).not_to include(first.api_key_digest)
    expect(Application.column_names).to contain_exactly("id", "name", "api_key_digest", "created_at", "updated_at")

    [ [ first, first_key ], [ second, second_key ] ].each do |application, key|
      get "/__auth_probe", headers: { "Authorization" => "Bearer #{key}" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("application_id" => application.id)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  it "returns the same 401 for missing, malformed and unknown keys without invoking the action" do
    key = ApplicationApiKey.generate
    [ nil, "Basic #{key}", "Bearer invalid", "Bearer #{key}", "Bearer #{key}, Bearer #{key}" ].each do |header|
      get "/__auth_probe", headers: header ? { "Authorization" => header } : {}
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "Unauthorized")
      expect(response.headers["WWW-Authenticate"]).to eq('Bearer realm="PulseLens"')
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  it "does not accept credentials from request parameters" do
    _, key = Application.issue_key!(name: "Parameter rejection")
    get "/__auth_probe", params: { api_key: key }
    expect(response).to have_http_status(:unauthorized)
  end

  it "does not disclose raw credentials or digest through application/SQL logs" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    loggers = [ Rails.logger, ActionController::Base.logger, ActiveRecord::Base.logger ].compact.uniq
    loggers.each { |sink| sink.broadcast_to(logger) }
    application, key = Application.issue_key!(name: "Log redaction")
    get "/__auth_probe", headers: { "Authorization" => "Bearer #{key}" }
    expect(response).to have_http_status(:ok)
    get "/__auth_probe", params: { api_key: key }
    expect(response).to have_http_status(:unauthorized)
    expect(output.string).to include("Processing by AuthenticationProbeController#show", "Application Create", "[FILTERED]")
    expect(output.string).not_to include(key, application.api_key_digest)
  ensure
    loggers&.each { |sink| sink.stop_broadcasting_to(logger) }
  end

  it "enforces unique digests in PostgreSQL" do
    application, = Application.issue_key!(name: "Unique digest")
    expect do
      Application.create!(name: "Duplicate digest", api_key_digest: application.api_key_digest)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "does not create an application when the name is blank" do
    expect { Application.issue_key!(name: " ") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "returns a generic 503 for a failed database lookup" do
    allow(Application).to receive(:authenticate_bearer).and_raise(ActiveRecord::ConnectionNotEstablished, "synthetic-private-detail")
    get "/__auth_probe", headers: { "Authorization" => "Bearer #{ApplicationApiKey.generate}" }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("error" => "Service unavailable")
  end
end
