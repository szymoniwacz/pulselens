require "rails_helper"
require "socket"
require "tempfile"
require "timeout"

RSpec.describe "Puma ingestion transport", :integration do
  def status_for(port, length: nil, chunks: nil, send_body: true)
    Timeout.timeout(15) do
      TCPSocket.open("127.0.0.1", port) do |socket|
        framing = chunks ? "Transfer-Encoding: chunked" : "Content-Length: #{length}"
        socket.write("POST /api/v1/events HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nConnection: close\r\n#{framing}\r\n\r\n")
        begin
          if chunks
            chunks.each { |size| socket.write("#{size.to_s(16)}\r\n#{'x' * size}\r\n") }
            socket.write("0\r\n\r\n")
          elsif send_body
            socket.write("x" * length)
          end
        rescue Errno::EPIPE, Errno::ECONNRESET
          # Puma is allowed to close an oversized request before the last bytes.
        end
        socket.gets.to_s.split[1].to_i
      end
    end
  end

  it "enforces exact and oversized lengths on real Content-Length and chunked requests" do
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
    log = Tempfile.new("pulselens-puma")
    pid = Process.spawn({ "RAILS_ENV" => "test", "PORT" => port.to_s }, "bundle", "exec", "puma", "-C", "config/puma.rb", out: log, err: log)
    Timeout.timeout(30) do
      loop do
        begin
          TCPSocket.open("127.0.0.1", port, &:close)
          break
        rescue Errno::ECONNREFUSED
          sleep 0.05
        end
      end
    end
    limit = IngestionBody::MAX_BYTES
    chunks = [ 64 * 1024 ] * 32
    # No credentials: a within-limit request reaches Rails and returns 401;
    # oversized bodies are rejected at the Puma boundary, even before auth.
    expect(status_for(port, length: limit)).to eq(401)
    expect(status_for(port, length: limit + 1, send_body: false)).to eq(413)
    expect(status_for(port, chunks: chunks)).to eq(401)
    expect(status_for(port, chunks: chunks + [ 1 ])).to eq(413)
  ensure
    if pid
      begin
        Process.kill("TERM", pid)
        Timeout.timeout(5) { Process.wait(pid) }
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      rescue Timeout::Error
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
    end
    log&.close!
  end
end
