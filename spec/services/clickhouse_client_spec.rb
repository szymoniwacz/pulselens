require "rails_helper"

RSpec.describe ClickhouseClient do
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { Net::HTTPOK.new("1.1", "200", "OK") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    %i[use_ssl= open_timeout= read_timeout= write_timeout= max_retries=].each do |setter|
      allow(http).to receive(setter)
    end
    allow(response).to receive(:body).and_return('{"data":[{"value":1}],"rows":1}')
    allow(http).to receive(:request).and_return(response)
  end

  it "uses typed parameters, an explicit deadline, and no retries or ambient proxy" do
    sql = "SELECT {value:String}"
    value = "a'\\\t\n&"
    expect(http).to receive(:max_retries=).with(0)
    expect(http).to receive(:open_timeout=).with(2)
    expect(http).to receive(:request).once do |request|
      params = URI.decode_www_form(URI.parse(request.path).query).to_h
      expect(params).to include("param_value" => "a'" + "\\\\" + "\\t" + "\\n&", "wait_end_of_query" => "1")
      expect(request.body).to eq(sql)
      expect(request.body).not_to include(value)
      response
    end
    expect(described_class.new(url: "http://localhost:8123").query(sql, bindings: { value: value })).to eq([ { "value" => 1 } ])
    expect(Net::HTTP).to have_received(:new).with("localhost", 8123, nil)
  end

  it "fails closed on a malformed or late-error response" do
    allow(response).to receive(:body).and_return('{"data":[],"rows":0} trailing exception')
    expect { described_class.new.query("SELECT 1") }.to raise_error(described_class::Unavailable)
    allow(response).to receive(:body).and_return('{"data":[],"rows":0,"exception":"secret"}')
    expect { described_class.new.query("SELECT 1") }.to raise_error(described_class::Unavailable, "Invalid ClickHouse query response")
  end

  it "does not retry an ambiguous write and does not expose transport details" do
    expect(http).to receive(:request).once.and_raise(Net::ReadTimeout.new("secret"))
    expect { described_class.new.execute("INSERT INTO events VALUES (1)") }.to raise_error(described_class::Unavailable) do |error|
      expect(error.message).not_to include("secret")
      expect(error.cause).to be_nil
    end
  end

  it "does not accept a successful status with an error body for a write" do
    allow(response).to receive(:body).and_return("Code: 42. secret")
    expect { described_class.new.execute("INSERT INTO events VALUES (1)") }.to raise_error(described_class::Unavailable, "ClickHouse did not confirm the operation")
  end

  it "rejects credentials in the URL without echoing them" do
    expect { described_class.new(url: "http://user:secret@localhost:8123") }.to raise_error(described_class::Unavailable, "Invalid ClickHouse endpoint")
  end
end
