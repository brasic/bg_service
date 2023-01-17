#!/usr/bin/env ruby
require 'socket'

raise 'want port' unless ARGV[0]

%w[TERM INT].each { |sig| trap(sig) { puts "shutdown on #{sig}"; exit } }

Socket.tcp_server_loop('127.0.0.1', Integer(ARGV[0])) do |sock, _|
  $stderr.puts "accepted connection"
  Thread.new do
    IO.copy_stream(sock, sock)
  ensure
    sock.close
  end
end
