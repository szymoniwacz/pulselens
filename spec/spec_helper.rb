RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_excluding integration: true unless ENV["RUN_SERVICE_SPECS"] == "1"
  config.filter_run_excluding outage: true unless ENV["EXPECT_UNAVAILABLE"]
  Kernel.srand config.seed
end
