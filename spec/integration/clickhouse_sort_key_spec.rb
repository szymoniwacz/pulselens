require "rails_helper"
require "securerandom"

RSpec.describe "ClickHouse sorting key evidence", :integration do
  it "compares date-only and name-filtered query plans for equal data" do
    client = ClickhouseClient.new
    suffix = SecureRandom.hex(6)
    tables = { date_first: "sort_date_#{suffix}", name_first: "sort_name_#{suffix}" }
    schema = Rails.root.join("db/clickhouse/001_create_events.sql").read
    tables.each do |kind, table|
      ddl = schema.sub("IF NOT EXISTS events", table)
      ddl = ddl.sub("application_id, occurred_at, name, event_id", "application_id, name, occurred_at, event_id") if kind == :name_first
      client.execute(ddl)
      client.execute(<<~SQL)
        INSERT INTO #{table}
        SELECT
          toUUID(if(number % 2 = 0, '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')),
          toUUID(concat('00000000-0000-0000-0000-', leftPad(toString(number), 12, '0'))),
          concat('event_', toString(intDiv(number, 2) % 8)),
          concat('user_', toString(number % 2000)),
          toDateTime64('2026-11-01 00:00:00', 3, 'UTC') + toIntervalDay(intDiv(number, 16) % 28) + toIntervalSecond(intDiv(number, 448)),
          toDateTime64('2026-11-30 00:00:00', 3, 'UTC'),
          'ios', 'PL', '{}'
        FROM numbers(131072)
      SQL
    end

    filters = {
      date_only: "",
      name_filtered: " AND name = 'event_1'"
    }
    filters.each do |shape, extra|
      counts = tables.map do |kind, table|
        sql = <<~SQL.squish
          SELECT count() AS count FROM #{table}
          WHERE application_id = toUUID('00000000-0000-0000-0000-000000000001')
          AND occurred_at >= '2026-11-12 00:00:00' AND occurred_at < '2026-11-13 00:00:00'#{extra}
        SQL
        plan = client.query("EXPLAIN indexes = 1 #{sql} SETTINGS use_query_condition_cache = 0, use_skip_indexes_on_data_read = 0")
                     .map { |row| row.fetch("explain") }.join("\n")
        expect(plan).to include("PrimaryKey", "Granules:")
        puts "SORT KEY #{kind} / #{shape}:\n#{plan}"
        client.query(sql).first.fetch("count").to_i
      end
      expect(counts.first).to be > 0
      expect(counts.uniq.length).to eq(1)
    end
  ensure
    # Only the unique tables created in the isolated test database, never events.
    tables&.each_value { |table| client.execute("DROP TABLE IF EXISTS #{table}") }
  end
end
