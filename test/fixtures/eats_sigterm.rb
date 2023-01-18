#!/usr/bin/env ruby
# A server that swallows and ignores SIGTERM and ignores it.
require 'socket'

raise 'want port' unless ARGV[0]

%w[TERM].each { |sig| trap(sig) { puts "got #{sig} but ignoring" } }

Socket.tcp_server_loop('127.0.0.1', Integer(ARGV[0])) do |sock, _|
  Thread.new do
    IO.copy_stream(sock, sock)
  ensure
    sock.close
  end
end
