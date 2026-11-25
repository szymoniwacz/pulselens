require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"

# Internal SQL only. Values supplied by callers must use typed ClickHouse bindings.
class ClickhouseClient
  class Unavailable < StandardError; end

  CONNECT_TIMEOUT = 2
  QUERY_TIMEOUT = 15
  INSERT_TIMEOUT = 30

  def initialize(database: "pulselens_#{Rails.env}", url: ENV.fetch("CLICKHOUSE_URL", "http://127.0.0.1:8123"),
                 user: ENV.fetch("CLICKHOUSE_USER", "pulselens"), password: ENV.fetch("CLICKHOUSE_PASSWORD", ""))
    @uri = URI.parse(url)
    unless %w[http https].include?(@uri.scheme) && @uri.host && !@uri.userinfo && !@uri.query && !@uri.fragment && [ "", "/" ].include?(@uri.path)
      raise Unavailable, "Invalid ClickHouse endpoint", cause: nil
    end

    @database = database
    @user = user
    @password = password
  rescue URI::InvalidURIError
    raise Unavailable, "Invalid ClickHouse endpoint", cause: nil
  end

  def query(sql, bindings: {})
    body = request(sql, bindings: bindings, deadline: QUERY_TIMEOUT, settings: { default_format: "JSON" })
    result = JSON.parse(body)
    unless result.is_a?(Hash) && !result.key?("exception") && result["data"].is_a?(Array) &&
        result["rows"] == result["data"].length && result["data"].all? { |row| row.is_a?(Hash) }
      raise Unavailable, "Invalid ClickHouse query response", cause: nil
    end
    result.fetch("data")
  rescue JSON::ParserError
    raise Unavailable, "Invalid ClickHouse query response", cause: nil
  end

  def execute(sql)
    confirm_empty!(request(sql, bindings: {}, deadline: QUERY_TIMEOUT))
  end

  # Rows are normalized internal hashes, not raw HTTP payloads. One synchronous
  # INSERT for the entire batch; callers validate before invoking this boundary.
  def insert_events(rows)
    raise ArgumentError, "Empty event batch" if rows.empty?

    payload = rows.map do |row|
      JSON.generate(
        application_id: row.fetch(:application_id),
        event_id: row.fetch(:event_id),
        name: row.fetch(:name),
        user_id: row.fetch(:user_id),
        occurred_at: timestamp(row.fetch(:occurred_at)),
        received_at: timestamp(row.fetch(:received_at)),
        platform: row.fetch(:platform),
        country: row.fetch(:country),
        properties: JSON.generate(row.fetch(:properties))
      )
    end.join("\n")

    confirm_empty!(request("INSERT INTO events FORMAT JSONEachRow\n#{payload}",
                           bindings: {}, deadline: INSERT_TIMEOUT, settings: { async_insert: 0 }))
  end

  private

  def timestamp(value)
    value.getutc.strftime("%Y-%m-%d %H:%M:%S.%L")
  end

  # HTTP query parameters use ClickHouse's escaped format before URL encoding.
  def escaped_binding(value)
    value.to_s.gsub(/[\\\t\n\r\0]/) do |character|
      { "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n", "\r" => "\\r", "\0" => "\\0" }.fetch(character)
    end
  end

  def request(sql, bindings:, deadline:, settings: {})
    params = { database: @database, wait_end_of_query: 1, max_execution_time: [ deadline - 2, 1 ].max }.merge(settings)
    bindings.each do |name, value|
      raise ArgumentError, "Invalid binding name" unless name.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

      params["param_#{name}"] = escaped_binding(value)
    end
    http = Net::HTTP.new(@uri.host, @uri.port, nil)
    http.use_ssl = @uri.scheme == "https"
    http.open_timeout = CONNECT_TIMEOUT
    http.read_timeout = deadline
    http.write_timeout = deadline
    http.max_retries = 0
    post = Net::HTTP::Post.new("/?#{URI.encode_www_form(params)}")
    post.basic_auth(@user, @password)
    post["Accept-Encoding"] = "identity"
    post.body = sql

    response = Timeout.timeout(deadline) { http.request(post) }
    body = response.body.to_s
    exception_code = response["X-ClickHouse-Exception-Code"]
    unless response.is_a?(Net::HTTPSuccess) && (exception_code.nil? || exception_code == "0") &&
        (response.content_length.nil? || response.content_length == body.bytesize)
      raise Unavailable, "ClickHouse operation failed", cause: nil
    end

    body
  rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    # No raw server responses, URLs, SQL or credentials in public errors or causes.
    raise Unavailable, "ClickHouse unavailable or operation timed out", cause: nil
  end

  def confirm_empty!(body)
    raise Unavailable, "ClickHouse did not confirm the operation", cause: nil unless body.strip.empty?

    true
  end
end
