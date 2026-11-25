require "date"
require "digest"
require "time"

# Generates only synthetic data; independent of wall clock except received_at.
class SyntheticEventGenerator
  class Invalid < StandardError; end

  class Incomplete < StandardError
    attr_reader :confirmed_count

    def initialize(confirmed_count)
      @confirmed_count = confirmed_count
      super("Generation stopped after #{confirmed_count} confirmed events; the last batch outcome is unknown")
    end
  end

  VERSION = 1
  BATCH_SIZE = 10_000
  MAX_SEED = (2**64) - 1
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  TIMESTAMP = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z/
  NAMES = %w[app_open app_open app_open screen_view screen_view search purchase].freeze
  PLATFORMS = %w[ios ios android android web].freeze
  COUNTRIES = %w[US US PL DE GB JP].freeze

  attr_reader :count, :application_ids

  def initialize(count:, from:, to:, seed:, application_ids:, batch_size: BATCH_SIZE)
    @count = integer(count, "EVENT_COUNT")
    @seed = integer(seed, "SEED")
    @batch_size = integer(batch_size, "batch size")
    raise Invalid, "EVENT_COUNT must be at least 2" if @count < 2
    raise Invalid, "SEED must be an unsigned 64-bit integer" if @seed > MAX_SEED
    raise Invalid, "Invalid batch size" unless @batch_size.between?(1, BATCH_SIZE)
    unless application_ids.is_a?(Array) && application_ids.length == 2 && application_ids.uniq.length == 2 &&
        application_ids.all? { |id| id.is_a?(String) && UUID_PATTERN.match?(id) }
      raise Invalid, "APPLICATION_IDS must contain two distinct lowercase UUIDs"
    end

    @application_ids = application_ids.map { |id| id.dup.freeze }.freeze
    @from_ms = timestamp_ms(from, "FROM")
    @to_ms = timestamp_ms(to, "TO")
    raise Invalid, "Range must contain at least one representable millisecond" unless @from_ms < @to_ms

    @identity = [ VERSION, @count, @seed, @from_ms, @to_ms, *@application_ids ].join(":").freeze
  end

  def each_batch(received_at: Time.now.utc)
    return enum_for(:each_batch, received_at: received_at) unless block_given?

    rng = Random.new(@seed)
    span = @to_ms - @from_ms
    hot_span = (span + 2) / 3
    batch = []
    @count.times do |index|
      # Deliberately skewed application, time, user and event distributions.
      application_id = @application_ids[index % 3 == 0 ? 1 : 0]
      timestamp = @from_ms + rng.rand(rng.rand(100) < 70 ? hot_span : span)
      user = rng.rand(rng.rand(100) < 80 ? 16 : 256)
      batch << {
        application_id: application_id,
        event_id: event_uuid(index),
        name: NAMES.sample(random: rng),
        user_id: "synthetic-user-#{user}",
        occurred_at: Time.at(timestamp.div(1000), timestamp % 1000, :millisecond).utc,
        received_at: received_at,
        platform: PLATFORMS.sample(random: rng),
        country: COUNTRIES.sample(random: rng),
        properties: { "generator_version" => VERSION, "synthetic" => true }
      }
      if batch.length == @batch_size
        yield batch
        batch = []
      end
    end
    yield batch unless batch.empty?
  end

  def write(client: ClickhouseClient.new, received_at: Time.now.utc)
    confirmed = 0
    each_batch(received_at: received_at) do |batch|
      raise ClickhouseClient::Unavailable, "Insert not confirmed" unless client.insert_events(batch)

      confirmed += batch.length
    end
    confirmed
  rescue ClickhouseClient::Unavailable
    raise Incomplete.new(confirmed), cause: nil
  end

  private

  def integer(value, field)
    return value if value.is_a?(Integer) && value >= 0
    return Integer(value, 10) if value.is_a?(String) && value.match?(/\A[0-9]{1,20}\z/)

    raise Invalid, "Invalid #{field}"
  end

  def timestamp_ms(value, field)
    match = TIMESTAMP.match(value) if value.is_a?(String) && value.ascii_only?
    if match && Date.valid_date?(*match.captures.first(3).map(&:to_i)) &&
        match[4].to_i < 24 && match[5].to_i < 60 && match[6].to_i < 60
      timestamp = Time.iso8601(value).utc
      milliseconds = (timestamp.to_r * 1000).ceil
      return milliseconds if timestamp.year.between?(1900, 2299) && Time.at(Rational(milliseconds, 1000)).utc.year <= 2299
    end
    raise Invalid, "Invalid #{field} timestamp"
  rescue ArgumentError
    raise Invalid, "Invalid #{field} timestamp", cause: nil
  end

  # Custom deterministic UUID (version 8, RFC variant), based on run identity
  # and ordinal. Batch size and received_at are deliberately excluded.
  def event_uuid(index)
    hex = Digest::SHA256.hexdigest("#{@identity}:#{index}")[0, 32]
    hex[12] = "8"
    hex[16] = ((hex[16].to_i(16) & 3) | 8).to_s(16)
    [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
  end
end
