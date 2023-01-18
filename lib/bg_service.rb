# frozen_string_literal: true

require_relative 'bg_service/version'
require_relative 'bg_service/server'

module BgService
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
end
