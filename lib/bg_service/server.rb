# frozen_string_literal: true

require 'socket'

module BgService
  class Server
    class BaseError < RuntimeError; end
    class AlreadyRunning < BaseError; end

    # An error with debug data automatically included
    class DebugError < BaseError
      def initialize(msg, server)
        super("#{msg}\n#{extended_message(server)}")
      end

      def extended_message(server)
        <<~MSG.chomp
          cmd: #{server.cmd.inspect}
          exit status: #{server.exit_status || "(unknown)" }
          server output:\n#{server.logs}
        MSG
      end
    end

    class CrashedOnStartup < DebugError; end
    class UnexpectedStatus < DebugError; end
    class TimedOut < DebugError; end
    class InvalidState < DebugError; end

    DEFAULT_TIMEOUT = 10
    SLEEP_INTERVAL = 0.02 # 20ms

    attr_reader :exit_status, :cmd

    def initialize(cmd, port:, env: {}, boot_timeout: DEFAULT_TIMEOUT)
      @cmd = cmd
      @env = env
      @port = port
      @tmpdir = Dir.mktmpdir
      @out = File.join(@tmpdir, 'out')
      @err = File.join(@tmpdir, 'err')
      @boot_timeout = boot_timeout
    end

    def start
      if @start_attempted
        raise InvalidState.new("cannot start a server that has already been stopped", self)
      end
      @start_attempted = now
      if listening?
        raise AlreadyRunning, "port #{@port} is already in use, refusing to start #{@cmd.inspect}"
      end

      @pid = spawn(@env, *@cmd, out: @out, err: @err)
      @started_at = now
      block_until_ready
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def block_until_ready
      while (now - @started_at) < @boot_timeout
        case status
        when :listening then return
        when :starting then sleep SLEEP_INTERVAL
        when :not_running then raise CrashedOnStartup.new("process exited before listening on port #{@port}", self)
        else
          raise UnexpectedStatus.new(status, self)
        end
      end
      stop
      raise TimedOut.new("not listening after #{@boot_timeout} seconds", self)
    end

    def logs
      return @final_out if @final_out
      out = prefix_log(@out, 'out') 
      err = prefix_log(@err, 'err')
      "#{out}#{err.chomp}"
    end

    def prefix_log(path, msg)
      lines = File.readlines(path)
      padding = lines.size.to_s.size
      lines.map.with_index { |line, i| "  #{msg} #{i.to_s.rjust(padding, "0")}: #{line}" }.join.tap do |str|
        return "#{msg}: <empty>\n" if str.empty?
      end
    rescue Errno::ENOENT
      "#{msg}: (no log file)"
    end

    def stop
      if @pid
        Process.kill 'TERM', @pid
        wait_status(nonblock: false)
        cleanup
        freeze # prevent further use
        nil
      end
    end

    def cleanup
      @final_out = logs
      FileUtils.remove_entry @tmpdir
    end

    def listening?
      TCPSocket.open('127.0.0.1', @port).close
      true
    rescue Errno::ECONNREFUSED
      false
    end

    def running?
      return false unless @pid

      wait_status.nil?
    end

    def status
      return :not_running if !running?
      listening? ? :listening : :starting
    end

    def wait_status(nonblock: true)
      @wait_status ||= begin
        flags = nonblock ? Process::WNOHANG : 0
        _, status = Process.wait2(@pid, flags)
        if status
          @pid = nil
          @exit_status = status
        end
      end
    end
  end
end
