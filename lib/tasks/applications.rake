namespace :applications do
  desc "Create a local demo application and display its API key once"
  task create: :environment do
    name = ENV.fetch("APPLICATION_NAME", "")
    if name.blank? || !Rails.env.local?
      abort "Use a local development/test environment and set APPLICATION_NAME"
    end

    application, key = Application.issue_key!(name: name)
    puts "Application ID: #{application.id}"
    puts "API key (shown once): #{key}"
  rescue ActiveRecord::ActiveRecordError
    abort "Application creation failed"
  end
end
