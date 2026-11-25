require "rails_helper"

RSpec.describe SyntheticEventGenerator do
  let(:ids) { %w[00000000-0000-0000-0000-000000000001 00000000-0000-0000-0000-000000000002] }
  let(:parameters) do
    { count: 600, seed: 42, from: "2026-11-01T01:00:00+01:00", to: "2026-11-04T00:00:00Z", application_ids: ids }
  end

  def logical(rows)
    rows.map { |row| row.except(:received_at) }
  end

  it "reproduces logical events independently of batch size and receipt time" do
    first = described_class.new(**parameters, batch_size: 7).each_batch(received_at: Time.utc(2026, 11, 5)).to_a.flatten
    second = described_class.new(**parameters, batch_size: 31).each_batch(received_at: Time.utc(2026, 11, 6)).to_a.flatten
    expect(logical(first)).to eq(logical(second))
    expect(first.first[:received_at]).not_to eq(second.first[:received_at])
    expect(first.map { |row| row.fetch(:event_id) }.uniq.length).to eq(600)
    expect(first.first[:event_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    changed = described_class.new(**parameters.merge(seed: 43)).each_batch.first
    expect(logical(changed)).not_to eq(logical(first))
  end

  it "has bounded batches, deterministic skew, returning users and multiple dimensions" do
    batches = described_class.new(**parameters, batch_size: 73).each_batch.to_a
    expect(batches.map(&:length)).to eq([ 73 ] * 8 + [ 16 ])
    rows = batches.flatten
    expect(rows.group_by { |row| row[:application_id] }.transform_values(&:length)).to eq(ids.first => 400, ids.last => 200)
    expect(rows.map { |row| row[:occurred_at] }).to all(be >= Time.utc(2026, 11, 1))
    expect(rows.map { |row| row[:occurred_at] }).to all(be < Time.utc(2026, 11, 4))
    expect(rows.count { |row| row[:occurred_at] < Time.utc(2026, 11, 2) }).to be > 300
    rows.group_by { |row| row[:application_id] }.each_value do |events|
      expect(events.map { |row| row[:user_id] }.uniq.length).to be < events.length
      expect(events.map { |row| row[:name] }.uniq).to contain_exactly("app_open", "screen_view", "search", "purchase")
      expect(events.map { |row| row[:platform] }.uniq).to contain_exactly("ios", "android", "web")
      expect(events.map { |row| row[:country] }.uniq.length).to be > 1
    end
  end

  it "preserves half-open millisecond membership and allocates the smallest valid count to both apps" do
    rows = described_class.new(**parameters.merge(count: 2, from: "2026-11-01T00:00:00.0001Z", to: "2026-11-01T00:00:00.0011Z")).each_batch.first
    expect(rows.map { |row| row[:application_id] }).to contain_exactly(*ids)
    expect(rows.map { |row| row[:occurred_at] }).to all(eq(Time.iso8601("2026-11-01T00:00:00.001Z")))
  end

  it "rejects invalid counts, seeds, mappings and timestamps before writing" do
    [ { count: 1 }, { count: "2x" }, { seed: -1 }, { seed: 2**64 }, { application_ids: [ ids.first, ids.first ] },
      { application_ids: [ ids.first ] }, { application_ids: [ ids.first, "invalid" ] }, { batch_size: 0 }, { batch_size: 10_001 },
      { from: "2026-11-01" }, { from: "2026-02-30T00:00:00Z" }, { from: "2026-11-04T00:00:00Z" },
      { from: "2026-11-01T00:00:00.0001Z", to: "2026-11-01T00:00:00.0002Z" } ].each do |invalid|
      expect { described_class.new(**parameters.merge(invalid)) }.to raise_error(described_class::Invalid)
    end
  end

  it "stops after an ambiguous batch without retrying or generating subsequent batches" do
    client = instance_double(ClickhouseClient)
    expect(client).to receive(:insert_events).with(an_instance_of(Array)).ordered.and_return(true)
    expect(client).to receive(:insert_events).with(an_instance_of(Array)).ordered.and_raise(ClickhouseClient::Unavailable, "private details")
    expect do
      described_class.new(**parameters, batch_size: 100).write(client: client)
    end.to raise_error(described_class::Incomplete) do |error|
      expect(error.confirmed_count).to eq(100)
      expect(error.message).not_to include("private details")
      expect(error.cause).to be_nil
    end
  end
end
