Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  # Health endpoints must remain reachable even when PostgreSQL is stopped.
  config.active_record.migration_error = false
  config.active_record.verbose_query_logs = false
  config.hosts = [ "localhost", "127.0.0.1", "::1" ]
end
