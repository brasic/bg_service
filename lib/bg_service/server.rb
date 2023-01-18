# frozen_string_literal: true

require 'socket'

module BgService
  # A network server that listens for incoming connections to be run as a
  # background process.
  class Server
    # Wait this long for the server to start listening before giving up
    DEFAULT_BOOT_TIMEOUT = 10
    # After sending a TERM signal, wait this long for the process to exit
    # before sending a KILL signal
    DEFAULT_TERM_TIMEOUT = 1
    SLEEP_INTERVAL = 0.005 # 5ms (while waiting for the server to start or stop)

    attr_reader :exit_status, :cmd

    def initialize(cmd, port:, env: {}, boot_timeout: DEFAULT_BOOT_TIMEOUT, term_timeout: DEFAULT_TERM_TIMEOUT)
      @cmd = cmd
      @env = env
      @port = port
      @tmpdir = Dir.mktmpdir
      @out = File.join(@tmpdir, 'out')
      @err = File.join(@tmpdir, 'err')
      @boot_timeout = boot_timeout
      @term_timeout = term_timeout
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
        s=status
        if s == :starting
          sleep SLEEP_INTERVAL
        elsif s == :listening
          return
        elsif s == :not_running
          raise CrashedOnStartup.new("process exited before listening on port #{@port}", self)
        else
          raise UnexpectedStatus.new("invariant violated: status was #{s.inspect}", self)
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
      return "#{msg}: <missing>\n"
    end

    def stop
      if @pid
        wait_for_exit
        cleanup
        freeze # prevent further use
      end
    end

    # Give the process @kill_timeout seconds to exit after sending a TERM
    # signal and then forcibly terminate it with SIGKILL.
    def wait_for_exit
      Process.kill 'TERM', @pid
      termed_at = now
      loop do
        break if wait_status
        if (now - termed_at) > @term_timeout
          Process.kill 'KILL', @pid
        end
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

    def wait_status
      @wait_status ||= begin
        _, status = Process.wait2(@pid, Process::WNOHANG)
        if status
          @pid = nil
          @exit_status = status
        end
      end
    end
  end
end
