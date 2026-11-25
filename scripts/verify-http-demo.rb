# Test-only clean-checkout walkthrough using the actual loopback Puma server.
require "json"
require "net/http"
require "nokogiri"
require "open3"
require "securerandom"
require "socket"
require "tempfile"
require "timeout"
require "uri"

abort "HTTP walkthrough requires RAILS_ENV=test" unless ENV["RAILS_ENV"] == "test"

# Never include response bodies, subprocess output or credentials in failures.
def check(condition, message)
  abort message unless condition
end

def request(port, path, params: {}, key: nil, payload: nil)
  target = params.empty? ? path : "#{path}?#{URI.encode_www_form(params)}"
  http = Net::HTTP.new("127.0.0.1", port, nil)
  http.open_timeout = 2
  http.read_timeout = 15
  http.write_timeout = 15
  http.max_retries = 0
  req = payload ? Net::HTTP::Post.new(target) : Net::HTTP::Get.new(target)
  req["Authorization"] = "Bearer #{key}" if key
  if payload
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(payload)
  end
  Timeout.timeout(20) { http.request(req) }
end

def dashboard(port, id, total, users, key: nil)
  response = request(port, "/", params: { application_id: id, from: "2026-11-01", to: "2026-12-01" })
  check(response.code == "200", "Dashboard HTTP status failed")
  check(!key || !response.body.include?(key), "Dashboard exposed a credential")
  page = Nokogiri::HTML(response.body)
  check(page.at_css("#total-events")&.text == total.to_s, "Dashboard event total mismatch")
  check(page.at_css("#unique-users")&.text == users.to_s, "Dashboard unique user total mismatch")
  rows = page.css("#daily-values tbody tr")
  check(rows.length == 30 && rows.sum { |row| row.css("td").first.text.to_i } == total, "Dashboard daily values mismatch")
  page
end

report = JSON.parse(File.read(ARGV.fetch(0)))
check(report.dig("environment", "environment") == "test", "Expected test benchmark report")
apps = report.dig("dataset", "applications")
check(apps.length == 2, "Expected two benchmark applications")
port = TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] }
log = Tempfile.new("pulselens-http-demo")
pid = nil
begin
  pid = Process.spawn({ "RAILS_ENV" => "test", "PORT" => port.to_s }, "bundle", "exec", "puma", "-C", "config/puma.rb", out: log, err: log)
  Timeout.timeout(30) do
    loop do
      begin
        check(request(port, "/up").code == "200", "Liveness failed")
        break
      rescue Errno::ECONNREFUSED
        sleep 0.1
      end
    end
  end
  check(request(port, "/ready").code == "200", "Readiness failed")

  output, _stderr, status = Open3.capture3({ "RAILS_ENV" => "test", "APPLICATION_NAME" => "HTTP walkthrough #{SecureRandom.uuid}" }, "bin/rails", "applications:create")
  check(status.success?, "Application creation failed")
  match = /\AApplication ID: ([0-9a-f-]{36})\nAPI key \(shown once\): ([0-9a-f]{64})\n\z/.match(output)
  check(!match.nil?, "Unexpected application creation output")
  id, key = match.captures
  event = { event_id: SecureRandom.uuid, name: "app_open", user_id: "synthetic-user-1", occurred_at: "2026-11-02T00:30:00+01:00",
            platform: "ios", country: "PL", properties: { screen: "home" } }
  response = request(port, "/api/v1/events", key: key, payload: { events: [ event ] })
  check(response.code == "201" && JSON.parse(response.body) == { "accepted" => 1 }, "HTTP ingestion failed")
  response = request(port, "/api/v1/analytics", key: key, params: { from: "2026-11-01T00:00:00Z", to: "2026-11-04T00:00:00Z", platform: "ios" })
  expected = { "total_events" => 1, "unique_users" => 1,
               "daily" => [ { "date" => "2026-11-01", "events" => 1, "active_users" => 1 },
                            { "date" => "2026-11-02", "events" => 0, "active_users" => 0 },
                            { "date" => "2026-11-03", "events" => 0, "active_users" => 0 } ],
               "top_events" => [ { "name" => "app_open", "count" => 1 } ] }
  check(response.code == "200" && JSON.parse(response.body) == expected, "HTTP analytics mismatch")
  dashboard(port, id, 1, 1, key: key)
  apps.zip([ 666_666, 333_334 ]).each do |app, count|
    check(app.fetch("counts").fetch("events") == count, "Benchmark fixture count mismatch")
    dashboard(port, app.fetch("application_id"), count, 256, key: key)
  end
  puts "Verified real loopback HTTP: readiness, operator key creation, ingestion 201, exact UTC analytics and all three rendered dashboards (1 / 666666 / 333334 events)."
ensure
  if pid
    begin
      Process.kill("TERM", pid)
      Timeout.timeout(5) { Process.wait(pid) }
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    rescue Timeout::Error
      Process.kill("KILL", pid)
      Process.wait(pid)
    end
  end
  log.close!
end
