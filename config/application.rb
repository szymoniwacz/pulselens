require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module PulseLens
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.time_zone = "UTC"
    config.generators.test_framework :rspec
    config.filter_parameters += %i[authorization api_key api_key_digest password secret token]
  end
end
