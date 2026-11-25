require "socket"

# Send chunks faster than read_timeout without ever finishing the response.
# A subsequent connection can return a healthy response.
class StallingHttpPeer
  attr_reader :closed, :requests

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @closed = Queue.new
    @requests = 0
    @normal = false
    @thread = Thread.new do
      loop do
        socket = @server.accept
        @socket = socket
        headers = []
        while (line = socket.gets) && line != "\r\n"
          headers << line
        end
        length = headers.grep(/Content-Length:/i).first.split(":", 2).last.to_i
        socket.read(length)
        @requests += 1
        if @normal
          socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n1\n")
        else
          socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
          begin
            loop do
              break if IO.select([ socket ], nil, nil, 0.02) && socket.read(1).nil?
              socket.write("1\r\n1\r\n")
            end
          rescue Errno::ECONNRESET, Errno::EPIPE
            # A timed-out HTTP client may reset instead of gracefully closing.
          end
          @closed << true
        end
        socket.close
      end
    rescue IOError, Errno::EBADF
      # Listener shutdown during test cleanup.
    end
  end

  def port
    @server.addr[1]
  end

  def respond_normally!
    @normal = true
  end

  def close
    @server.close
    @socket&.close unless @socket&.closed?
    @thread.join(1) || @thread.kill.join
  end
end
