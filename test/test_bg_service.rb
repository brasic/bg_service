# frozen_string_literal: true

require 'test_helper'

class TestBgService < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::BgService::VERSION
  end

  def teardown
    @svc.stop if @svc
  end

  def test_basic_usage
    @svc = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    @svc.start
    assert_predicate @svc, :running?
    assert_predicate @svc, :listening?
    assert_nil @svc.exit_status
    @svc.stop
    assert_equal :not_running, @svc.status
    refute_nil @svc.exit_status
    assert_predicate @svc.exit_status, :success?
  end

  def test_knows_output_of_process
    @svc = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    @svc.start
    assert_predicate @svc, :running?
    s = TCPSocket.open('127.0.0.1', 8833)
    s.puts "hi"
    res = s.gets.chomp
    s.close
    assert_equal 'hi', res
    @svc.stop
    assert_equal(<<-OUT.chomp, @svc.logs)
  out 0: shutdown on TERM
  err 0: accepted connection
  err 1: accepted connection
    OUT
  end

  def test_idempotent_stop
    @svc = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    @svc.start
    @svc.stop
    assert_predicate @svc.exit_status, :success?
    @svc.stop
  end

  def test_prevents_double_start
    @svc1 = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    @svc1.start
    @svc2 = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    ex = assert_raises { @svc2.start }
    assert_equal 'port 8833 is already in use, refusing to start ["test/fixtures/echo_server.rb", "8833"]', ex.message
  ensure
    @svc1.stop if @svc1
  end

  def test_prevents_start_after_stop
    @svc = BgService::Server.new(['test/fixtures/echo_server.rb', '8833'], port: 8833)
    @svc.start
    @svc.stop
    assert_equal :not_running, @svc.status
    refute_nil @svc.exit_status
    assert_predicate @svc.exit_status, :success?
    ex = assert_raises(BgService::Server::InvalidState) { @svc.start }
    assert_match(/cannot start a server that has already been stopped/, ex.message)
  end

  def test_is_helpful_when_server_does_not_start
    @svc = BgService::Server.new(['test/fixtures/misbehaving_server.rb'], port: 9876)
    ex = assert_raises(BgService::Server::CrashedOnStartup) { @svc.start }
    assert_log_match(<<~MSG.chomp, ex.message)
      process exited before listening on port 9876
      cmd: ["test/fixtures/misbehaving_server.rb"\]
      exit status: pid XXX exit 1
      server output:
        out 0: starting...
        err 0: FATAL ERROR
        err 1: (have some debug data)
    MSG
  end

  def test_handles_timeouts
    @svc = BgService::Server.new("sleep 10", port: 9876, boot_timeout: 0.1)
    ex = assert_raises(BgService::Server::TimedOut) { @svc.start }
    assert_log_match(<<~MSG.chomp, ex.message)
      not listening after 0.1 seconds
      cmd: "sleep 10"
      exit status: pid XXX SIGTERM (signal 15)
      server output:
      out: <empty>
      err: <empty>
    MSG
  end

  def test_handles_servers_that_eat_sigterm
    @svc = BgService::Server.new(['test/fixtures/eats_sigterm.rb', '7890'], port: 7890)
    @svc.start
    @svc.stop
    assert_equal 9, @svc.exit_status.termsig # got SIGKILLed  
  end
end
