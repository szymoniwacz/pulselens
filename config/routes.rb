Rails.application.routes.draw do
  get "/up", to: "rails/health#show", as: :rails_health_check
  get "/ready", to: "readiness#show"
  get "/api/v1/analytics", to: "api/v1/analytics#show"
end
