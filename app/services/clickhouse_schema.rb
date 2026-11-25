# Local operator-only schema setup. Each version is an idempotent SQL statement.
# Never drop or truncate an existing database as part of setup.
class ClickhouseSchema
  def initialize(environment: Rails.env)
    unless %w[development test].include?(environment.to_s)
      raise ArgumentError, "ClickHouse schema setup is local development/test only"
    end

    @database = "pulselens_#{environment}"
  end

  def apply
    ClickhouseClient.new(database: "default").execute("CREATE DATABASE IF NOT EXISTS #{@database}")
    client = ClickhouseClient.new(database: @database)
    Rails.root.glob("db/clickhouse/*.sql").sort.each do |migration|
      client.execute(migration.read)
    end
    true
  end
end
