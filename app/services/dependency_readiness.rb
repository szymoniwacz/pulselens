require "net/http"
require "resolv"
require "timeout"

# Connectivity probes only. Event inserts, schema setup and analytical SQL belong to later goals.
class DependencyReadiness
  PROBE_TIMEOUT = 2

  def call
    { postgresql: check("PostgreSQL") { postgresql_ready? },
      clickhouse: check("ClickHouse") { clickhouse_ready? } }
  end

  private

  def check(name)
    yield ? "ok" : "unavailable"
  rescue StandardError => error
    # Never include connection URLs, response bodies, credentials or exception messages.
    Rails.logger.warn("#{name} readiness failed (#{error.class.name})")
    "unavailable"
  end

  def postgresql_ready?
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PROBE_TIMEOUT
    hostaddr = before_deadline(deadline) { Resolv.getaddress(config.fetch(:host)) }
    # Own the handle before starting any interruptible network operation. A
    # timeout inside PG.connect could otherwise orphan its unfinished socket.
    # A dedicated probe never borrows or damages application pool connections.
    connection = PG::Connection.connect_start(
      **config.slice(:port, :password, :sslmode, :options),
      host: config.fetch(:host), hostaddr: hostaddr,
      user: config.fetch(:username), dbname: config.fetch(:database)
    )
    before_deadline(deadline) do
      loop do
        case connection.connect_poll
        when PG::PGRES_POLLING_OK then break
        when PG::PGRES_POLLING_READING then connection.socket_io.wait_readable
        when PG::PGRES_POLLING_WRITING then connection.socket_io.wait_writable
        else raise PG::ConnectionBad, "PostgreSQL connection failed"
        end
      end
      connection.setnonblocking(true)
      connection.exec("SELECT 1") { |result| result.getvalue(0, 0) == "1" }
    end
  ensure
    connection&.finish unless connection&.finished?
  end

  def before_deadline(deadline)
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise Timeout::Error if remaining <= 0
    Timeout.timeout(remaining) { yield }
  end

  def clickhouse_ready?
    uri = URI.parse(ENV.fetch("CLICKHOUSE_URL", "http://127.0.0.1:8123"))
    unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && [ "", "/" ].include?(uri.path)
      raise ArgumentError, "Invalid ClickHouse endpoint"
    end

    http = Net::HTTP.new(uri.host, uri.port, nil) # Do not send local credentials through ambient proxies.
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 2
    http.read_timeout = 2
    http.write_timeout = 2
    http.max_retries = 0
    request = Net::HTTP::Post.new("/")
    request.basic_auth(ENV.fetch("CLICKHOUSE_USER", "pulselens"), ENV.fetch("CLICKHOUSE_PASSWORD", ""))
    request.body = "SELECT 1 FORMAT TabSeparated"
    response = Timeout.timeout(PROBE_TIMEOUT) { http.request(request) }
    response.is_a?(Net::HTTPSuccess) && response.body.strip == "1"
  end
end
