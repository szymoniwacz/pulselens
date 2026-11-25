module Api
  module V1
    class EventsController < Api::BaseController
      def create
        body = request.env[IngestionBody::BODY_KEY]
        raise JSON::ParserError unless body&.valid_encoding?

        rows = EventBatch.new(payload: JSON.parse(body), application_id: current_application.id).rows
        unless ClickhouseClient.new.insert_events(rows)
          raise ClickhouseClient::Unavailable, "Insert not confirmed", cause: nil
        end
        render json: { accepted: rows.length }, status: :created
      rescue JSON::ParserError, EncodingError
        render json: { error: "Malformed JSON" }, status: :bad_request
      rescue EventBatch::Invalid => error
        render json: { error: error.message, field: error.field, index: error.index }, status: :unprocessable_entity
      rescue ClickhouseClient::Unavailable
        render json: { error: "Service unavailable" }, status: :service_unavailable
      end
    end
  end
end
