# frozen_string_literal: true

require 'test_helper'

class ServerTest < Minitest::Test
  def setup
    @server = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
  end

  def teardown
    @server&.stop
    @server1&.stop
    @server2&.stop
  end

  def test_can_stop_without_starting
    @server.stop
  end

  def test_basic_usage
    @server.start
    assert_predicate @server, :running?
    assert_predicate @server, :listening?
    assert_nil @server.exit_status
    @server.stop
    assert_equal :not_running, @server.status
    refute_nil @server.exit_status
    assert_predicate @server.exit_status, :success?
  end

  def test_can_pass_env_vars
    @server = BgService::Server.new('echo ENV1 is $ENV1', port: 8833, boot_timeout: 0.1, env: { 'ENV1' => 'foo' })
    ex = assert_raises { @server.start }
    assert_log_match(<<~MSG.chomp, ex.message)
      process exited before listening on port 8833
      cmd: "echo ENV1 is $ENV1"
      exit status: pid XXX exit 0
      server output:
        out 0: ENV1 is foo
      err: <empty>
    MSG
  end 

  def test_knows_output_of_process
    @server.start
    assert_predicate @server, :running?
    s = TCPSocket.open('127.0.0.1', 8833)
    s.puts "hi"
    res = s.gets.chomp
    s.close
    assert_equal 'hi', res
    @server.stop
    assert_equal(<<-OUT.chomp, @server.logs)
  out 0: shutdown on TERM
  err 0: accepted connection
  err 1: accepted connection
    OUT
  end

  def test_idempotent_stop
    @server.start
    @server.stop
    assert_predicate @server.exit_status, :success?
    @server.stop
  end

  def test_prevents_double_start
    @server1 = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    @server1.start
    @server2 = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    ex = assert_raises(BgService::AlreadyRunning) { @server2.start }
    assert_equal(
      'port 8833 is already in use, refusing to start ["test/fixtures/echo_server.rb", "8833"]',
      ex.message
    )
  end

  def test_prevents_start_after_stop
    @server = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    @server.start
    @server.stop
    assert_equal :not_running, @server.status
    refute_nil @server.exit_status
    assert_predicate @server.exit_status, :success?
    ex = assert_raises(BgService::InvalidState) { @server.start }
    assert_match(/cannot start a server that has already been stopped/, ex.message)
  end

  def test_is_helpful_when_server_does_not_start
    @server = BgService::Server.new(['test/fixtures/misbehaving_server.rb'], port: 9876)
    ex = assert_raises(BgService::CrashedOnStartup) { @server.start }
    assert_log_match(<<~MSG.chomp, ex.message)
      process exited before listening on port 9876
      cmd: ["test/fixtures/misbehaving_server.rb"]
      exit status: pid XXX exit 1
      server output:
        out 0: starting...
        err 0: FATAL ERROR
        err 1: (have some debug data)
    MSG
  end

  def test_handles_servers_that_dont_listen
    @server = BgService::Server.new("sleep 10", port: 9876, boot_timeout: 0.01)
    ex = assert_raises(BgService::TimedOut) { @server.start }
    assert_log_match(<<~MSG.chomp, ex.message)
      not listening after 0.01 seconds
      cmd: "sleep 10"
      exit status: pid XXX SIGTERM (signal 15)
      server output:
      out: <empty>
      err: <empty>
    MSG
  end

  def test_forcibly_kills_servers_that_ignore_sigterm
    @server = BgService::Server.new(['test/fixtures/eats_sigterm.rb', '7890'], port: 7890, term_timeout: 0.1)
    @server.start
    @server.stop
    assert_equal 9, @server.exit_status.termsig # got SIGKILLed  
  end

  def test_unexpected_statuses
    @server.stub(:status, :weird_unknown_value) do
      ex = assert_raises(BgService::UnexpectedStatus) { @server.start }
      assert_equal(<<~MSG.chomp, ex.message)
        invariant violated: status was :weird_unknown_value
        cmd: [\"test/fixtures/echo_server.rb\", \"8833\"]
        exit status: (unknown)
        server output:
        out: <empty>
        err: <empty>
      MSG
    end
  end

  def test_handles_missing_logfiles
    impl = -> path { raise Errno::ENOENT, "No such file or directory @ rb_sysopen - #{path}" }
    File.stub(:readlines, impl) do
      @server.start
      @server.stop
      assert_equal(<<~OUT.chomp, @server.logs)
        out: <missing>
        err: <missing>
      OUT
    end
  end
end
