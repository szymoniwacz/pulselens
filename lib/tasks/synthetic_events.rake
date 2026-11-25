namespace :events do
  desc "Append deterministic synthetic events for two existing local demo applications"
  task generate: :environment do
    abort "Use a local development/test environment" unless Rails.env.local?

    generator = SyntheticEventGenerator.new(
      count: ENV["EVENT_COUNT"], from: ENV["FROM"], to: ENV["TO"], seed: ENV["SEED"],
      application_ids: ENV.fetch("APPLICATION_IDS", "").split(",", -1).map(&:strip)
    )
    unless Application.where(id: generator.application_ids).pluck(:id).sort == generator.application_ids.sort
      abort "Both demo applications must already exist"
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    confirmed = generator.write
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts "Confirmed #{confirmed} synthetic events; batch limit #{SyntheticEventGenerator::BATCH_SIZE}; elapsed #{format('%.3f', elapsed)}s"
  rescue SyntheticEventGenerator::Invalid, SyntheticEventGenerator::Incomplete => error
    abort error.message
  rescue ActiveRecord::ActiveRecordError, ClickhouseClient::Unavailable
    abort "Generator could not access a dependency"
  end
end
