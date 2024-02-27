# frozen_string_literal: true

require 'rabrick'

module Rabrick
  module Handler
    def run(app, **options)
      environment  = ENV.fetch('RACK_ENV', 'development')
      default_host = environment == 'development' ? 'localhost' : nil

      options[:BindAddress] ||= default_host
      options[:Port] ||= 8080
      options[:App] = app

      @server = ::Rabrick::HTTPServer.new(options)
      yield @server if block_given?
      @server.start
    end

    def shutdown
      if @server
        @server.shutdown
        @server = nil
      end
    end
  end
end
