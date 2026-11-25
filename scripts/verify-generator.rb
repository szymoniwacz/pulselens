# Run via Rails runner in the isolated test environment, never production.
require "rake"
abort "Generator verification requires RAILS_ENV=test" unless Rails.env.test?

first, = Application.issue_key!(name: "Million-event verification first")
second, = Application.issue_key!(name: "Million-event verification second")
ENV.update("EVENT_COUNT" => "1000000", "SEED" => "42", "FROM" => "2026-11-01T00:00:00Z",
           "TO" => "2026-12-01T00:00:00Z", "APPLICATION_IDS" => [ first.id, second.id ].join(","))
Rails.application.load_tasks unless Rake::Task.task_defined?("events:generate")
Rake::Task["events:generate"].invoke

client = ClickhouseClient.new
[ [ first.id, 666_666 ], [ second.id, 333_334 ] ].each do |id, expected|
  row = client.query(<<~SQL, bindings: { application: id }).first
    SELECT count() AS events, uniqExact(event_id) AS event_ids, uniqExact(user_id) AS users,
           uniqExact(name) AS names, uniqExact(platform) AS platforms, uniqExact(country) AS countries,
           min(occurred_at) AS first_event, max(occurred_at) AS last_event
    FROM events WHERE application_id = {application:UUID}
  SQL
  counts = %w[events event_ids users names platforms countries].to_h { |key| [ key, Integer(row.fetch(key)) ] }
  unless counts.fetch("events") == expected && counts.fetch("event_ids") == expected &&
      counts.fetch("users").between?(2, expected - 1) && counts.fetch("names") == 4 &&
      counts.fetch("platforms") == 3 && counts.fetch("countries") == 5 &&
      row.fetch("first_event") >= "2026-11-01 00:00:00.000" && row.fetch("last_event") < "2026-12-01 00:00:00.000"
    abort "Unexpected generator verification counts or range"
  end
  puts "Application #{id}: #{counts}; #{row.fetch('first_event')} through #{row.fetch('last_event')}"
end
puts "Verified 1,000,000 events, two applications, 100 batches of at most 10,000 rows; no data deleted."
