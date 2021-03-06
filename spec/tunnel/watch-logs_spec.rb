require "spec_helper"

module CFTools::Tunnel
  describe WatchLogs do
    let(:director_uri) { "https://some-director.com:25555" }

    let(:director) { Bosh::Cli::Client::Director.new(director_uri) }

    let(:stream) { double }

    let(:vms) do
      [ { "ips" => ["1.2.3.4"], "job_name" => "api_z1", "index" => 0 },
        { "ips" => ["1.2.3.5"], "job_name" => "runner_z1", "index" => 0 },
        { "ips" => ["1.2.3.6"], "job_name" => "runner_z1", "index" => 1 }
      ]
    end

    let(:deployments) do
      [{ "name" => "some-deployment",  "releases" => [{ "name" => "cf-release" }] }]
    end

    def mock_cli
      any_instance_of(described_class) do |cli|
        mock(cli)
      end
    end

    def stub_cli
      any_instance_of(described_class) do |cli|
        stub(cli)
      end
    end

    before do
      director.stub(:list_deployments => deployments)
      director.stub(:fetch_vm_state => vms)
      described_class.any_instance.stub(:connected_director => director)

      stream.stub(:stream)
      described_class.any_instance.stub(:stream_for => stream)
    end

    it "connects to the given director" do
      expect_any_instance_of(described_class).to \
        receive(:connected_director).with(
          "some-director.com", "someuser@somehost.com").
        and_return(director)

      cf %W[watch-logs some-director.com --gateway someuser@somehost.com]
    end

    context "when no gateway user/host is specified" do
      it "defaults to vcap@director" do
        expect_any_instance_of(described_class).to \
          receive(:connected_director).with(
            "some-director.com", "vcap@some-director.com").
            and_return(director)

        cf %W[watch-logs some-director.com]
      end
    end

    context "when there are no jobs to log" do
      let(:vms) { [] }

      it "fails with a message" do
        cf %W[watch-logs some-director.com]
        expect(error_output).to say("No locations found.")
      end
    end

    context "when there are jobs to log" do
      it "streams their locations" do
        expect(stream).to receive(:stream).with(hash_including(
          ["api_z1", 0] => anything,
          ["runner_z1", 0] => anything,
          ["runner_z1", 1] => anything))

        cf %W[watch-logs some-director.com]
      end

      it "pretty-prints their log entries" do
        entry1_time = Time.new(2011, 06, 21, 1, 2, 3)
        entry2_time = Time.new(2011, 06, 21, 1, 2, 4)
        entry3_time = Time.new(2011, 06, 21, 1, 2, 5)

        entry1 = LogEntry.new(
          "api_z1/0",
          %Q[{"message":"a","timestamp":#{entry1_time.to_f},"log_level":"info"}],
          :stdout)

        entry2 = LogEntry.new(
          "runner_z1/1",
          %Q[{"message":"b","timestamp":#{entry2_time.to_f},"log_level":"warn","data":{"foo":"bar"}}],
          :stdout)

        entry3 = LogEntry.new(
          "runner_z1/0",
          %Q[{"message":"c","timestamp":#{entry3_time.to_f},"log_level":"error"}],
          :stdout)

        expect(stream).to receive(:stream).and_yield(entry1).and_yield(entry2).and_yield(entry3)

        cf %W[watch-logs some-director.com]

        expect(output).to say("api_z1/0      01:02:03 AM  info    a  \n")
        expect(output).to say("runner_z1/1   01:02:04 AM  warn    b  {\"foo\"=>\"bar\"}\n")
        expect(output).to say("runner_z1/0   01:02:05 AM  error   c  \n")
      end

      context "and components were specified" do
        it "streams their locations" do
          expect(stream).to receive(:stream).with(["api_z1", 0] => anything)
          cf %W[watch-logs some-director.com api_z1]
        end
      end
    end
  end
end
