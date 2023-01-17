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
    assert_equal(<<~MSG.chomp, ex.message)
      cannot start a server that has already been stopped
      cmd: ["test/fixtures/echo_server.rb", "8833"]
      exit status: 0
      server output:
      out: <empty>
      err: <empty>
    MSG
  end

  def test_is_helpful_when_server_does_not_start
    @svc = BgService::Server.new(['test/fixtures/misbehaving_server.rb'], port: 9876)
    ex = assert_raises(BgService::Server::CrashedOnStartup) { @svc.start }
    assert_equal(<<~MSG.chomp, ex.message)
      process exited before listening on port 9876
      cmd: ["test/fixtures/misbehaving_server.rb"]
      exit status: 1
      server output:
        out 0: starting...
        err 0: FATAL ERROR
        err 1: (have some debug data)
    MSG
  end
end
