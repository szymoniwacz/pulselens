require "rails_helper"
require_relative "../support/stalling_tcp_proxy"

RSpec.describe "PostgreSQL transport deadline", :integration do
  [ :handshake, :query ].each do |phase|
    it "closes a stalled #{phase} socket, preserves the application pool and recovers" do
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      proxy = StallingTcpProxy.new(host: config.fetch(:host), port: config.fetch(:port))
      stub_const("ReadinessRegressionRecord", Class.new(ActiveRecord::Base) { self.abstract_class = true })
      ReadinessRegressionRecord.establish_connection(config.merge(port: proxy.port, pool: 1, sslmode: "disable"))
      pool = ReadinessRegressionRecord.connection_pool
      pooled_connection = pool.with_connection do |connection|
        expect(connection.select_value("SELECT 1")).to eq(1)
        connection.raw_connection
      end
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(ReadinessRegressionRecord.connection_db_config)
      probe_connections = []
      allow(PG::Connection).to receive(:connect_start).and_wrap_original do |original, **parameters|
        original.call(**parameters).tap do |connection|
          probe_connections << connection
          if phase == :query
            # Arm only after the real handshake; the actual SELECT still uses
            # the real driver and transport, with its bytes withheld upstream.
            allow(connection).to receive(:exec).and_wrap_original do |query, *args, &block|
              proxy.stall!
              query.call(*args, &block)
            end
          end
        end
      end
      proxy.stall! if phase == :handshake

      # A guard keeps a broken implementation from hanging the test runner.
      result = Timeout.timeout(8) { DependencyReadiness.new.call }
      expect(Timeout.timeout(3) { proxy.blocked.pop }).to eq(true)
      expect(result).to eq(postgresql: "unavailable", clickhouse: "ok")
      expect(probe_connections.length).to eq(1)
      expect(probe_connections.first.finished?).to be(true)
      expect(Timeout.timeout(3) { proxy.closed.pop }).to eq(true)
      expect(pool.stat).to include(busy: 0, dead: 0, waiting: 0)
      expect(pooled_connection.finished?).to be(false)

      proxy.resume!
      # Recovery must run without rearming the proxy at query entry.
      allow(PG::Connection).to receive(:connect_start).and_call_original
      expect(DependencyReadiness.new.call).to eq(postgresql: "ok", clickhouse: "ok")
      pool.with_connection do |connection|
        expect(connection.raw_connection).to equal(pooled_connection)
        expect(connection.select_value("SELECT 1")).to eq(1)
      end
      expect(pool.stat).to include(busy: 0, dead: 0, waiting: 0)
    ensure
      ReadinessRegressionRecord.remove_connection if defined?(ReadinessRegressionRecord)
      proxy&.close
    end
  end
end
