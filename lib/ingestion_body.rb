require "json"
require "stringio"

# The local API has one POST route. Capture its bounded raw body before Rails
# parameter parsing/logging; the authenticated controller parses it explicitly.
# Future POST routes must explicitly opt into their own body-handling contract.
class IngestionBody
  MAX_BYTES = 2 * 1024 * 1024
  READ_BYTES = 64 * 1024
  BODY_KEY = "pulselens.ingestion_body".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless env["REQUEST_METHOD"] == "POST"

    length = env["CONTENT_LENGTH"]
    if length && !length.empty?
      return error(400, "Invalid request length") unless length.match?(/\A[0-9]+\z/)
      return error(413, "Request body too large") if length.to_i > MAX_BYTES
    end

    body = read_body(env["rack.input"])
    return error(413, "Request body too large") if body.bytesize > MAX_BYTES

    env[BODY_KEY] = body.force_encoding(Encoding::UTF_8)
    # Do not expose the original body to Rails' implicit parameter parser or
    # raw malformed-JSON logging. Rack still owns the original input's lifetime.
    env["rack.input"] = StringIO.new("")
    env["CONTENT_LENGTH"] = "0"
    env.delete("HTTP_TRANSFER_ENCODING")
    @app.call(env)
  end

  private

  def read_body(input)
    body = String.new(encoding: Encoding::BINARY)
    while input && body.bytesize <= MAX_BYTES
      chunk = input.read([ READ_BYTES, MAX_BYTES + 1 - body.bytesize ].min)
      break if chunk.nil? || chunk.empty?

      body << chunk
    end
    body
  end

  def error(status, message)
    body = JSON.generate(error: message)
    [ status, { "content-type" => "application/json", "content-length" => body.bytesize.to_s, "cache-control" => "no-store" }, [ body ] ]
  end
end
