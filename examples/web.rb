# frozen_string_literal: true

# The first web seam is the useful part of Rack: a callable Ruby object accepts
# an environment Hash and returns [status, headers, body]. Rails needs far more
# stdlib, gems, persistence, clocks, and socket behavior than this tiny kernel.
require "rubyos"

app = RubyOS::HTTP::Router.new
  .get("/") { "Ruby blocks are the router.\n" }
status, headers, body = app.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/")
raise "bad Rack-shaped response" unless status == 200 && headers && body.join.include?("Ruby blocks")
puts "web lesson: #{status} #{body.join.strip}"
puts "web lesson: PASS"
