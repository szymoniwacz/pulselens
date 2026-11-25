# Application identity comes from trusted server context, never request filters.
class EventAnalytics
  def initialize(application_id:, filters:, client: ClickhouseClient.new)
    @filters = filters
    @client = client
    @bindings = {
      application: application_id,
      from: filters.from_milliseconds.strftime("%Y-%m-%d %H:%M:%S.%L"),
      to: filters.to_milliseconds.strftime("%Y-%m-%d %H:%M:%S.%L")
    }
    conditions = [
      "application_id = {application:UUID}",
      "occurred_at >= {from:DateTime64(3, 'UTC')}",
      "occurred_at < {to:DateTime64(3, 'UTC')}"
    ]
    # Fixed predicates only. Never interpolate caller-supplied values into SQL.
    if filters.name
      conditions << "name = {name:String}"
      @bindings[:name] = filters.name
    end
    if filters.platform
      conditions << "platform = {platform:String}"
      @bindings[:platform] = filters.platform
    end
    if filters.country
      conditions << "country = {country:String}"
      @bindings[:country] = filters.country
    end
    @where = conditions.join(" AND ")
  end

  def call
    total_rows = @client.query(<<~SQL, bindings: @bindings)
      SELECT count() AS total_events, uniqExact(user_id) AS unique_users
      FROM events WHERE #{@where}
    SQL
    unless total_rows.one?
      raise ClickhouseClient::Unavailable, "Invalid analytics response", cause: nil
    end
    totals = total_rows.first
    daily_rows = @client.query(<<~SQL, bindings: @bindings)
      SELECT toDate32(occurred_at, 'UTC') AS day, count() AS events,
             uniqExact(user_id) AS active_users
      FROM events WHERE #{@where}
      GROUP BY day ORDER BY day ASC
    SQL
    top_rows = @client.query(<<~SQL, bindings: @bindings)
      SELECT name, count() AS event_count FROM events WHERE #{@where}
      GROUP BY name ORDER BY event_count DESC, name ASC LIMIT 10
    SQL
    daily_by_date = daily_rows.index_by { |row| row.fetch("day") }
    {
      total_events: count_value(totals, "total_events"),
      unique_users: count_value(totals, "unique_users"),
      daily: @filters.dates.map do |date|
        day = date.iso8601
        row = daily_by_date[day]
        { date: day, events: row ? count_value(row, "events") : 0,
          active_users: row ? count_value(row, "active_users") : 0 }
      end,
      top_events: top_rows.map { |row| { name: row.fetch("name"), count: count_value(row, "event_count") } }
    }
  rescue KeyError, ArgumentError, TypeError
    raise ClickhouseClient::Unavailable, "Invalid analytics response", cause: nil
  end

  private

  def count_value(row, key)
    count = row.fetch(key)
    return count if count.is_a?(Integer) && count >= 0
    return Integer(count, 10) if count.is_a?(String) && count.match?(/\A[0-9]+\z/)

    raise ClickhouseClient::Unavailable, "Invalid analytics response", cause: nil
  end
end
