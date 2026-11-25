require_relative "../lib/ingestion_body"

threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", "5"))
threads threads_count, threads_count
bind "tcp://127.0.0.1:#{Integer(ENV.fetch('PORT', '3000'))}"
http_content_length_limit IngestionBody::MAX_BYTES
plugin :tmp_restart
