require "rails_helper"

RSpec.describe "Synthetic event generator", :integration do
  it "writes bounded batches to real storage and appends the same logical events on rerun" do
    first, = Application.issue_key!(name: "Generator first")
    second, = Application.issue_key!(name: "Generator second")
    generator = SyntheticEventGenerator.new(count: 61, seed: 42, from: "2026-11-01T00:00:00Z", to: "2026-11-04T00:00:00Z",
                                            application_ids: [ first.id, second.id ], batch_size: 7)
    client = ClickhouseClient.new
    expect(generator.write(client: client, received_at: Time.utc(2026, 11, 5))).to eq(61)
    expect(generator.write(client: client, received_at: Time.utc(2026, 11, 6))).to eq(61)

    [ [ first.id, 40 ], [ second.id, 21 ] ].each do |id, count|
      rows = client.query(<<~SQL, bindings: { application: id })
        SELECT event_id, name, user_id, occurred_at, platform, country, properties,
               count() AS copies, uniqExact(received_at) AS receipts
        FROM events WHERE application_id = {application:UUID}
        GROUP BY event_id, name, user_id, occurred_at, platform, country, properties
        ORDER BY event_id
      SQL
      expect(rows.length).to eq(count)
      expect(rows.map { |row| row.fetch("event_id") }.uniq.length).to eq(count)
      expect(rows.map { |row| row.fetch("copies").to_i }).to all(eq(2))
      expect(rows.map { |row| row.fetch("receipts").to_i }).to all(eq(2))
      expect(rows.map { |row| row.fetch("occurred_at") }).to all(be >= "2026-11-01 00:00:00.000")
      expect(rows.map { |row| row.fetch("occurred_at") }).to all(be < "2026-11-04 00:00:00.000")
    end
  end
end
