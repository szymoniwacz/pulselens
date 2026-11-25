require "rails_helper"
require "stringio"

RSpec.describe IngestionBody do
  let(:app) { ->(env) { [ 200, {}, [ env.fetch(described_class::BODY_KEY) ] ] } }
  let(:middleware) { described_class.new(app) }

  def request(input, length: nil)
    env = { "REQUEST_METHOD" => "POST", "rack.input" => input }
    env["CONTENT_LENGTH"] = length.to_s if length
    middleware.call(env)
  end

  it "rejects an oversized declared length before reading or dispatching" do
    input = instance_double(StringIO)
    expect(input).not_to receive(:read)
    expect(request(input, length: described_class::MAX_BYTES + 1).first).to eq(413)
  end

  it "reads at most the limit plus one byte, even when length is absent or understated" do
    [ nil, 1 ].each do |length|
      input = StringIO.new("x" * (described_class::MAX_BYTES + 100))
      expect(request(input, length: length).first).to eq(413)
      expect(input.pos).to eq(described_class::MAX_BYTES + 1)
    end
  end

  it "accepts exactly the byte limit and handles short reads" do
    input = StringIO.new("x" * described_class::MAX_BYTES)
    status, _, body = request(input)
    expect(status).to eq(200)
    expect(body.first.bytesize).to eq(described_class::MAX_BYTES)
    short = instance_double(StringIO)
    allow(short).to receive(:read).with(described_class::READ_BYTES).and_return("a", "b", nil)
    expect(request(short).last).to eq([ "ab" ])
  end

  it "prevents downstream implicit body parsing and leaves GET requests untouched" do
    downstream = ->(env) do
      expect(env["rack.input"].read).to eq("")
      expect(env["CONTENT_LENGTH"]).to eq("0")
      expect(env[described_class::BODY_KEY]).to eq("{broken")
      [ 200, {}, [] ]
    end
    expect(described_class.new(downstream).call({ "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new("{broken") }).first).to eq(200)
    env = { "REQUEST_METHOD" => "GET" }
    expect(described_class.new(->(actual) { expect(actual).to equal(env); [ 200, {}, [] ] }).call(env).first).to eq(200)
  end
end
