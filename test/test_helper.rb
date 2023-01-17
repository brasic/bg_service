# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "bg_service"

require "minitest/autorun"


def assert_log_match(expected, actual)
  processed = actual.gsub(/pid \d+/, 'pid XXX')
  assert_equal(expected, processed)
end
