Rails.application.routes.draw do
  root "dashboard#show"
  get "/up", to: "rails/health#show", as: :rails_health_check
  get "/ready", to: "readiness#show"
  post "/api/v1/events", to: "api/v1/events#create", format: false
  get "/api/v1/analytics", to: "api/v1/analytics#show"
end
