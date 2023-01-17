# frozen_string_literal: true

require_relative 'bg_service/version'
require_relative 'bg_service/server'

module BgService
  def self.with_server
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'out')
      err = File.join(dir, 'err')
      server = Server.new(out:, err:)
      server.start
      begin
        yield server
      rescue StandardError
        out_log = File.readlines(out).map { |l| "out: #{l}" }.join
        err_log = File.readlines(err).map { |l| "err: #{l}" }.join
        puts "logs:\n#{out_log}\n#{err_log}"
        raise
      ensure
        server.stop
      end
    end
  end
end
