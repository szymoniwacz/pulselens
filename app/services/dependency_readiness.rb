require "net/http"

# Connectivity probes only. Event inserts, schema setup and analytical SQL belong to later goals.
class DependencyReadiness
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
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.select_value("SELECT 1").to_i == 1
    end
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
    response = http.request(request)
    response.is_a?(Net::HTTPSuccess) && response.body.strip == "1"
  end
end
