namespace :clickhouse do
  desc "Apply versioned local ClickHouse schema without deleting data"
  task setup: :environment do
    ClickhouseSchema.new.apply
    puts "ClickHouse schema ready"
  rescue ClickhouseClient::Unavailable
    abort "ClickHouse schema setup failed"
  end
end
