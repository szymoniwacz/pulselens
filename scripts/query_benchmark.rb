require "digest"
require "json"
require "etc"
require "open3"
require "time"

# Benchmark-only adapter. Reuse the same bounded HTTP transport and actual
# EventAnalytics SQL, retaining the JSON statistics that normal queries discard.
module QueryBenchmark
  FROM = "2026-11-01T00:00:00Z".freeze
  TO = "2026-12-01T00:00:00Z".freeze
  REPETITIONS = 5
  SETTINGS = { default_format: "JSON", use_query_cache: 0, use_query_condition_cache: 0, output_format_write_statistics: 1 }.freeze
  SHAPES = { "date_only" => {}, "dimensions" => { name: "app_open", platform: "ios", country: "PL" } }.freeze

  class MeasuredClient < ClickhouseClient
    attr_reader :measurements

    def initialize(**options)
      super
      @measurements = []
    end

    def query(sql, bindings: {})
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = request(sql, bindings: bindings, deadline: QUERY_TIMEOUT, settings: SETTINGS)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      result = JSON.parse(body)
      unless result.is_a?(Hash) && !result.key?("exception") && result["data"].is_a?(Array) &&
          result["rows"] == result["data"].length && result["data"].all? { |row| row.is_a?(Hash) }
        raise Unavailable, "Invalid benchmark query result", cause: nil
      end
      stats = result.fetch("statistics")
      server_seconds = Float(stats.fetch("elapsed"))
      rows = Integer(stats.fetch("rows_read"))
      bytes = Integer(stats.fetch("bytes_read"))
      unless server_seconds.finite? && server_seconds >= 0 && rows >= 0 && bytes >= 0
        raise Unavailable, "Invalid benchmark statistics", cause: nil
      end
      @measurements << { sql: sql, bindings: bindings.dup, server_seconds: server_seconds,
                         client_seconds: elapsed, rows_read: rows, bytes_read: bytes }
      result.fetch("data")
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError
      raise Unavailable, "Invalid benchmark query result or statistics", cause: nil
    end
  end

  module_function

  def verify_dataset(ids, client: ClickhouseClient.new)
    unless ids.length == 2 && ids.uniq.length == 2 && ids.all? { |id| SyntheticEventGenerator::UUID_PATTERN.match?(id) }
      raise ArgumentError, "APPLICATION_IDS must contain two distinct lowercase UUIDs"
    end
    unless Application.where(id: ids).count == 2
      raise ArgumentError, "Both benchmark applications must exist"
    end

    ids.zip([ 666_666, 333_334 ]).map do |id, expected|
      row = client.query(<<~SQL, bindings: { application: id }).fetch(0)
        SELECT count() AS events, uniqExact(event_id) AS event_ids, uniqExact(user_id) AS users,
               uniqExact(name) AS names, uniqExact(platform) AS platforms, uniqExact(country) AS countries,
               min(occurred_at) AS first_event, max(occurred_at) AS last_event,
               countIf(JSONExtractUInt(properties, 'generator_version') != 1 OR NOT JSONExtractBool(properties, 'synthetic')) AS unexpected_properties
        FROM events WHERE application_id = {application:UUID}
      SQL
      counts = %w[events event_ids users names platforms countries unexpected_properties].to_h { |key| [ key, Integer(row.fetch(key)) ] }
      unless counts == { "events" => expected, "event_ids" => expected, "users" => 256, "names" => 4, "platforms" => 3,
                         "countries" => 5, "unexpected_properties" => 0 } &&
          row.fetch("first_event") >= "2026-11-01 00:00:00.000" && row.fetch("last_event") < "2026-12-01 00:00:00.000"
        raise ArgumentError, "Dataset does not match the documented million-event fixture; no data modified"
      end
      { application_id: id, counts: counts, first_event: row.fetch("first_event"), last_event: row.fetch("last_event") }
    end
  end

  def measure(application_id, client: MeasuredClient.new, repetitions: REPETITIONS)
    SHAPES.map do |name, dimensions|
      filters = AnalyticsFilters.new(from: FROM, to: TO, **dimensions)
      reference = nil
      queries = nil
      samples = repetitions.times.map do |index|
        client.measurements.clear
        result = EventAnalytics.new(application_id: application_id, filters: filters, client: client).call
        reference ||= result
        raise ArgumentError, "Analytics changed during measurement" unless result == reference

        descriptors = client.measurements.map { |sample| sample.slice(:sql, :bindings) }
        queries ||= descriptors
        unless queries == descriptors && descriptors.length == 3
          raise ArgumentError, "Unexpected analytics query sequence"
        end
        { repetition: index + 1, queries: client.measurements.map { |sample| sample.except(:sql, :bindings) } }
      end
      unless reference.fetch(:total_events) > 0 && reference.fetch(:unique_users) > 0
        raise ArgumentError, "Expected nonempty benchmark results"
      end
      { shape: name, filters: dimensions, queries: queries, result: reference,
        result_sha256: Digest::SHA256.hexdigest(JSON.generate(reference)), samples: samples }
    end
  end

  def command(*arguments)
    output, _stderr, status = Open3.capture3(*arguments)
    output.strip if status.success?
  rescue Errno::ENOENT
    nil
  end

  def linux_value(path, pattern)
    File.read(path)[pattern, 1] if File.file?(path)
  end

  def metadata(client: ClickhouseClient.new)
    {
      git_head: command("git", "rev-parse", "HEAD"), environment: Rails.env.to_s,
      ruby: RUBY_DESCRIPTION, rails: Rails.version,
      postgres: Application.connection.select_value("SHOW server_version"),
      clickhouse: client.query("SELECT version() AS version").fetch(0).fetch("version"),
      server_settings: client.query("SELECT name, value FROM system.settings WHERE name IN ('max_threads', 'max_memory_usage', 'use_query_cache', 'use_query_condition_cache') ORDER BY name"),
      host: Etc.uname.slice(:sysname, :release, :machine), host_logical_cpus: Etc.nprocessors,
      mac_model: command("sysctl", "-n", "hw.model"), mac_memory_bytes: command("sysctl", "-n", "hw.memsize"),
      linux_cpu_model: linux_value("/proc/cpuinfo", /^model name\s*:\s*(.+)$/),
      linux_memory_kib: linux_value("/proc/meminfo", /^MemTotal:\s*(\d+) kB$/),
      docker_engine_cpus_memory_bytes: command("docker", "info", "--format", "{{.ServerVersion}} {{.NCPU}} {{.MemTotal}}"),
      compose: command("docker", "compose", "version", "--short")
    }
  end

  def run(ids, generated: false)
    environment = metadata
    dataset = verify_dataset(ids)
    {
      report_version: 1, measured_at_utc: Time.now.utc.iso8601, environment: environment,
      dataset: { seed: 42, seed_provenance: generated ? "generated in this process" : "operator-declared; verified counts and dimensions, not seed identity",
                 generator_version: SyntheticEventGenerator::VERSION, from: FROM, to: TO, applications: dataset },
      measurement: { repetitions: REPETITIONS, settings: SETTINGS, query_order: "totals, daily, top names",
                     cache_method: "dataset verification precedes samples; no cache flush or restart; first observed is not cold",
                     client_seconds_scope: "bounded HTTP request and full response body, excluding JSON parse and Rails rendering",
                     application_id: ids.first, shapes: measure(ids.first) }
    }
  end
end
