class DashboardController < ApplicationController
  def show
    response.set_header("Cache-Control", "no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    return head :not_found unless Rails.env.local? && request.local?

    @applications = []
    @form = default_form
    query = request.query_parameters
    @form.merge!(query.slice(*@form.keys).select { |_, value| value.is_a?(String) })
    @applications = Application.order(:name, :id).pluck(:id, :name)
    return unless query.key?("application_id")

    application = @applications.find { |id, _| id == query["application_id"] }
    raise AnalyticsFilters::Invalid, "Select an existing demo application" unless application

    filters = AnalyticsFilters.new(**filter_arguments(query))
    @result = EventAnalytics.new(application_id: application.first, filters: filters).call
  rescue AnalyticsFilters::Invalid => error
    @error = error.message
    render :show, status: :unprocessable_entity
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::StatementInvalid, ClickhouseClient::Unavailable
    @error = "Analytics unavailable. Check the local database services and try again."
    render :show, status: :service_unavailable
  end

  private

  def default_form
    today = Time.now.utc.to_date
    { "application_id" => "", "from" => (today - 6).iso8601, "to" => (today + 1).iso8601,
      "name" => "", "platform" => "", "country" => "" }
  end

  def filter_arguments(query)
    values = { from: utc_midnight(query["from"], "from"), to: utc_midnight(query["to"], "to") }
    %w[name platform country].each do |field|
      next unless query.key?(field) && query[field] != ""

      values[field.to_sym] = query[field]
    end
    values
  end

  def utc_midnight(value, field)
    unless value.is_a?(String) && value.ascii_only? && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      raise AnalyticsFilters::Invalid, "Invalid #{field} date"
    end

    "#{value}T00:00:00Z"
  end
end
