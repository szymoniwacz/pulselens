require "rails_helper"
require_relative "../../scripts/query_benchmark"

RSpec.describe QueryBenchmark::MeasuredClient, :integration do
  it "captures real JSON statistics without changing returned query rows" do
    sql = "SELECT number AS n FROM numbers(3) WHERE number >= {minimum:UInt64} ORDER BY n"
    bindings = { minimum: 1 }
    client = described_class.new
    expect(client.query(sql, bindings: bindings)).to eq(ClickhouseClient.new.query(sql, bindings: bindings))
    expect(client.measurements.length).to eq(1)
    sample = client.measurements.first
    expect(sample).to include(sql: sql, bindings: bindings)
    %i[server_seconds client_seconds rows_read bytes_read].each do |key|
      expect(sample.fetch(key)).to be >= 0
    end
  end
end
