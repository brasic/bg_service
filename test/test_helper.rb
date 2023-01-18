# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  minimum_coverage line: 100, branch: 100
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "bg_service"
require "minitest/autorun"

# Become a session leader to make leaking processes less likely. As leader of
# the session, all processes we spawned will be sent SIGHUP when we exit.
Process.setsid

def assert_log_match(expected, actual)
  processed = actual.gsub(/pid \d+/, 'pid XXX')
  assert_equal(expected, processed)
end
