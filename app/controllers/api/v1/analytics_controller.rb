module Api
  module V1
    class AnalyticsController < Api::BaseController
      def show
        filters = AnalyticsFilters.new(**request.query_parameters.slice("from", "to", "name", "platform", "country").symbolize_keys)
        render json: EventAnalytics.new(application_id: current_application.id, filters: filters).call
      rescue AnalyticsFilters::Invalid => error
        render json: { error: error.message }, status: :unprocessable_entity
      rescue ClickhouseClient::Unavailable
        render json: { error: "Service unavailable" }, status: :service_unavailable
      end
    end
  end
end
