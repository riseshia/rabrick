# frozen_string_literal: true

require 'rackup'
require 'rabrick'
require 'rabrick/rackup_register'

class SampleServer
  def call(_env)
    [200, { "Content-Type" => "text/html" }, ["Request received"]]
  end
end

Rackup::Server.start(app: SampleServer.new)
