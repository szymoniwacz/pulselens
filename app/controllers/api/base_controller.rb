module Api
  # Only future API endpoints inherit this controller; health and dashboard do not.
  class BaseController < ActionController::API
    before_action :authenticate_application!

    private

    attr_reader :current_application

    def authenticate_application!
      response.set_header("Cache-Control", "no-store")
      @current_application = Application.authenticate_bearer(request.get_header("HTTP_AUTHORIZATION"))
      return if @current_application

      response.set_header("WWW-Authenticate", 'Bearer realm="PulseLens"')
      render json: { error: "Unauthorized" }, status: :unauthorized
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::StatementInvalid
      render json: { error: "Service unavailable" }, status: :service_unavailable
    end
  end
end
