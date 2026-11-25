require "date"
require "json"
require "time"

# All rows must be validated and normalized before the caller attempts a write.
class EventBatch
  class Invalid < StandardError
    attr_reader :field, :index

    def initialize(field, index = nil)
      @field = field
      @index = index
      super("Invalid event batch")
    end
  end

  MAX_EVENTS = 1000
  MAX_NAME_BYTES = 128
  MAX_USER_BYTES = 256
  MAX_PROPERTIES_BYTES = 16 * 1024
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  RESERVED = %w[application_id received_at].freeze

  def initialize(payload:, application_id:, received_at: Time.now.utc)
    @payload = payload
    @application_id = application_id
    @received_at = received_at.getutc
  end

  def rows
    raise Invalid.new("events") unless @payload.is_a?(Hash)
    reject_reserved!(@payload, nil)
    events = @payload["events"]
    unless events.is_a?(Array) && events.length.between?(1, MAX_EVENTS)
      raise Invalid.new("events")
    end

    events.map.with_index { |event, index| normalize(event, index) }
  end

  private

  def normalize(event, index)
    raise Invalid.new("events", index) unless event.is_a?(Hash)
    reject_reserved!(event, index)
    event_id = event["event_id"]
    unless event_id.is_a?(String) && event_id.ascii_only? && UUID.match?(event_id)
      raise Invalid.new("event_id", index)
    end
    name = required_string(event["name"], MAX_NAME_BYTES, "name", index)
    user_id = required_string(event["user_id"], MAX_USER_BYTES, "user_id", index)
    occurred_at = timestamp(event["occurred_at"], index)
    platform = event.fetch("platform", "unknown")
    country = event.fetch("country", "unknown")
    # Share the already approved dimension vocabulary with analytics.
    raise Invalid.new("platform", index) unless AnalyticsFilters::PLATFORMS.include?(platform)
    unless country == "unknown" || AnalyticsFilters::COUNTRIES.include?(country)
      raise Invalid.new("country", index)
    end
    properties = event.fetch("properties", {})
    validate_properties!(properties, index)

    { application_id: @application_id, event_id: event_id.downcase, name: name, user_id: user_id,
      occurred_at: occurred_at, received_at: @received_at, platform: platform, country: country, properties: properties }
  end

  def reject_reserved!(object, index)
    RESERVED.each { |field| raise Invalid.new(field, index) if object.key?(field) }
  end

  def required_string(value, limit, field, index)
    return value if value.is_a?(String) && value.valid_encoding? && value.bytesize <= limit && !value.strip.empty?

    raise Invalid.new(field, index)
  end

  def timestamp(value, index)
    match = AnalyticsFilters::TIMESTAMP.match(value) if value.is_a?(String) && value.ascii_only?
    if match && Date.valid_date?(*match.captures.first(3).map(&:to_i)) &&
        match[4].to_i < 24 && match[5].to_i < 60 && match[6].to_i < 60
      time = Time.iso8601(value).utc
      # The storage contract uses milliseconds. Truncate, never round into
      # a different second/day; validate the normalized UTC year first.
      return Time.at(Rational((time.to_r * 1000).floor, 1000)).utc if time.year.between?(1900, 2299)
    end
    raise Invalid.new("occurred_at", index)
  rescue ArgumentError
    raise Invalid.new("occurred_at", index), cause: nil
  end

  def validate_properties!(value, index)
    return if value.is_a?(Hash) && JSON.generate(value).bytesize <= MAX_PROPERTIES_BYTES

    raise Invalid.new("properties", index)
  rescue JSON::GeneratorError, JSON::NestingError, EncodingError
    raise Invalid.new("properties", index), cause: nil
  end
end
