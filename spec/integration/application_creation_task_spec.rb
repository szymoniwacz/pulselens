require "rails_helper"
require "rake"
require "stringio"

RSpec.describe "applications:create", :integration do
  let(:task) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("applications:create")
    Rake::Task["applications:create"]
  end

  around do |example|
    original_name = ENV["APPLICATION_NAME"]
    example.run
  ensure
    ENV["APPLICATION_NAME"] = original_name
    task.reenable
  end

  it "prints a single usable key only after creating the application" do
    ENV["APPLICATION_NAME"] = "Task demo #{SecureRandom.uuid}"
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output
    task.invoke
    $stdout = original_stdout

    application = Application.find_by!(name: ENV.fetch("APPLICATION_NAME"))
    match = /\AApplication ID: ([0-9a-f-]{36})\nAPI key \(shown once\): ([0-9a-f]{64})\n\z/.match(output.string)
    expect(match).not_to be_nil
    expect(match[1]).to eq(application.id)
    expect(ApplicationApiKey.digest(match[2])).to eq(application.api_key_digest)
  ensure
    $stdout = original_stdout
  end

  it "rejects a missing name without displaying a key" do
    ENV.delete("APPLICATION_NAME")
    expect do
      expect { task.invoke }.to raise_error(SystemExit)
    end.to output("Use a local development/test environment and set APPLICATION_NAME\n").to_stderr
  end

  it "reports a failed database write without printing a credential or private details" do
    ENV["APPLICATION_NAME"] = "Unavailable database"
    allow(Application).to receive(:issue_key!).and_raise(ActiveRecord::ConnectionNotEstablished, "synthetic-private-detail")
    expect do
      expect do
        expect { task.invoke }.to raise_error(SystemExit)
      end.to output("Application creation failed\n").to_stderr
    end.to output("").to_stdout
  end
end
