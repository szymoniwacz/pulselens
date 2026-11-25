# Run with bin/rails runner. Existing-data mode is read-only; fresh generation
# is opt-in, test-only and creates a fresh pair without deleting anything.
require_relative "query_benchmark"
abort "Benchmark requires a local development/test environment" unless Rails.env.local?

generated = ENV["BENCHMARK_GENERATE"] == "1"
if generated
  abort "Fresh benchmark generation requires RAILS_ENV=test" unless Rails.env.test?
  begin
    original_stdout = $stdout
    $stdout = $stderr
    load Rails.root.join("scripts/verify-generator.rb")
  ensure
    $stdout = original_stdout
  end
end
ids = ENV.fetch("APPLICATION_IDS", "").split(",", -1)
report = QueryBenchmark.run(ids, generated: generated)
puts JSON.pretty_generate(report)
