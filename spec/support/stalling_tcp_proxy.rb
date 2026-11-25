require "socket"

# Transparent local proxy. Once armed, it acknowledges client transport traffic
# but withholds it from the database, so server-side statement_timeout cannot help.
class StallingTcpProxy
  attr_reader :blocked, :closed

  def initialize(host:, port:)
    @server = TCPServer.new("127.0.0.1", 0)
    @blocked = Queue.new
    @closed = Queue.new
    @stall = false
    @sockets = []
    @workers = []
    @acceptor = Thread.new do
      loop do
        client = @server.accept
        upstream = TCPSocket.new(host, port)
        @sockets.concat([ client, upstream ])
        @workers << Thread.new(client, upstream) { |down, up| relay(down, up) }
      end
    rescue IOError, Errno::EBADF
      # Listener shutdown during test cleanup.
    end
  end

  def port
    @server.addr[1]
  end

  def stall!
    @stall = true
  end

  def resume!
    @stall = false
  end

  def close
    @server.close
    @acceptor.join(1) || @acceptor.kill.join
    @sockets.each { |socket| socket.close unless socket.closed? }
    @workers.each { |worker| worker.join(1) || worker.kill.join }
  end

  private

  def relay(client, upstream)
    loop do
      IO.select([ client, upstream ]).first.each do |source|
        data = source.readpartial(16_384)
        if @stall && source.equal?(client)
          @blocked << true
        else
          (source.equal?(client) ? upstream : client).write(data)
        end
      end
    end
  rescue EOFError, IOError, SystemCallError
    # Either client or server closed the interrupted transport.
  ensure
    client.close unless client.closed?
    upstream.close unless upstream.closed?
    @closed << true
  end
end
