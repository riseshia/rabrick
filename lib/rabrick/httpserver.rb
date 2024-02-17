# frozen_string_literal: true

#
# httpserver.rb -- HTTPServer Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httpserver.rb,v 1.63 2002/10/01 17:16:32 gotoyuzo Exp $

require 'io/wait'
require_relative 'server'
require_relative 'httputils'
require_relative 'httpstatus'
require_relative 'httprequest'
require_relative 'httpresponse'
require_relative 'accesslog'

module Rabrick
  class HTTPServerError < ServerError; end

  ##
  # An HTTP Server

  class HTTPServer < ::Rabrick::GenericServer
    ##
    # Creates a new HTTP server according to +config+
    #
    # An HTTP server uses the following attributes:
    #
    # :AccessLog:: An array of access logs.  See Rabrick::AccessLog
    # :BindAddress:: Local address for the server to bind to
    # :HTTPVersion:: The HTTP version of this server
    # :Port:: Port to listen on
    # :RequestTimeout:: Maximum time to wait between requests
    # :ServerAlias:: Array of alternate names for this server for virtual
    #                hosting
    # :ServerName:: Name for this server for virtual hosting

    def initialize(config = {}, default = Config::HTTP)
      super(config, default)
      @http_version = HTTPVersion.convert(@config[:HTTPVersion])

      @rack_app = nil

      unless @config[:AccessLog]
        @config[:AccessLog] = [
          AccessLog::COMMON_LOG_FORMAT,
          AccessLog::REFERER_LOG_FORMAT
        ]
      end
      @config[:ServerName] # Touch to load default value
      @config = Rabrick::Config.make_shareable(@config)
    end

    # It needs some time to refactor Whole inheritance structure of Rabrick to use Ractor,
    # so I just use Ractor for only this class.
    def start_ractor(passed_sock) # XXX Shadowing make fails to call ractor since it considered as assignment.
      ractor_args = {
        config: @config,
        http_version: @http_version,
        sock: passed_sock,
        status: @status,
      }

      Ractor.new(ractor_args) do |ractor_args|
        sock = ractor_args[:sock]

        begin
          begin
            addr = sock.peeraddr
            Rabrick::RactorLogger.debug "accept: #{addr[3]}:#{addr[1]}"
          rescue SocketError
            Rabrick::RactorLogger.debug "accept: <address unknown>"
            raise
          end

          Rabrick::RequestHandler.run(**ractor_args)
        rescue Errno::ENOTCONN
          Rabrick::RactorLogger.debug "Errno::ENOTCONN raised"
        rescue ServerError => e
          msg = "#{e.class}: #{e.message}\n\t#{e.backtrace[0]}"
          Rabrick::RactorLogger.error msg
        rescue Exception => e
          Rabrick::RactorLogger.error e
        ensure
          if addr
            Rabrick::RactorLogger.debug "close: #{addr[3]}:#{addr[1]}"
          else
            Rabrick::RactorLogger.debug "close: <address unknown>"
          end
          sock.close
        end
      end
    end

    ##
    # Processes requests on +sock+

    def run(sock)
      Rabrick::RequestHandler.run(
        config: @config,
        http_version: @http_version,
        sock: sock,
        status: @status,
      )
    end

    ##
    # Services +req+ and fills in +res+

    def service(req, res)
      if req.unparsed_uri == "*"
        if req.request_method == "OPTIONS"
          do_OPTIONS(req, res)
          raise HTTPStatus::OK
        end
        raise HTTPStatus::NotFound, "`#{req.unparsed_uri}' not found."
      end

      if @rack_app.nil?
        raise HTTPStatus::NotFound, "`#{req.unparsed_uri}' not found."
      end

      servlet, options = @rack_app

      req.script_name = script_name
      req.path_info = path_info
      si = servlet.get_instance(self, *options)
      Rabrick::RactorLogger.debug(format("%s is invoked.", si.class.name))
      si.service(req, res)
    end

    ##
    # The default OPTIONS request handler says GET, HEAD, POST and OPTIONS
    # requests are allowed.

    def do_OPTIONS(_req, res)
      res["allow"] = "GET,HEAD,POST,OPTIONS"
    end

    def mount_app(servlet, *options)
      Rabrick::RactorLogger.debug(format("%s is mounted on %s.", servlet.inspect, dir))
      @rack_app = [servlet, options]
    end

    ##
    # Logs +req+ and +res+ in the access logs.  +config+ is used for the
    # server name.

    def access_log(config, req, res)
      param = AccessLog.setup_params(config, req, res)
      @config[:AccessLog].each { |fmt|
        AccessLog.format(fmt + "\n", param)
        Rabrick::RactorAccessLogger.puts(AccessLog.format(fmt + "\n", param))
      }
    end

    ##
    # Creates the HTTPRequest used when handling the HTTP
    # request. Can be overridden by subclasses.
    def create_request(with_rabrick_config)
      HTTPRequest.new(with_rabrick_config)
    end

    ##
    # Creates the HTTPResponse used when handling the HTTP
    # request. Can be overridden by subclasses.
    def create_response(with_rabrick_config)
      HTTPResponse.new(with_rabrick_config)
    end
  end
end
