# frozen_string_literal: true

require 'io/wait'
require_relative 'server'
require_relative 'httpstatus'
require_relative 'httprequest'
require_relative 'httpresponse'
require_relative 'httpservlet'
require_relative 'accesslog'

module Rabrick
  module RequestHandler
    module_function

    ##
    # Processes requests on +sock+

    def run(config:, http_version:, sock:, status:, mount_tab:)
      loop do
        req = create_request(config)
        res = create_response(config)
        begin
          timeout = config[:RequestTimeout]
          while timeout > 0
            break if sock.to_io.wait_readable(0.5)
            break if status != :Running

            timeout -= 0.5
          end
          raise HTTPStatus::EOFError if timeout <= 0 || status != :Running
          raise HTTPStatus::EOFError if sock.eof?

          req.parse(sock)
          res.request_method = req.request_method
          res.request_uri = req.request_uri
          res.request_http_version = req.http_version
          res.keep_alive = req.keep_alive?

          service(mount_tab, req, res)
        rescue HTTPStatus::EOFError, HTTPStatus::RequestTimeout => e
          puts e.backtrace.join("\n")
          res.set_error(e)
        rescue HTTPStatus::Error => e
          puts e.backtrace.join("\n")
          Rabrick::RactorLogger.error(e.message)
          res.set_error(e)
        rescue HTTPStatus::Status => e
          puts e.backtrace.join("\n")
          res.status = e.code
        rescue StandardError => e
          puts e.backtrace.join("\n")
          Rabrick::RactorLogger.error(e)
          res.set_error(e, true)
        ensure
          if req.request_line
            if req.keep_alive? && res.keep_alive?
              req.fixup()
            end
            res.send_response(sock)
            access_log(config, req, res)
          end
        end
        break if http_version < "1.1"
        break unless req.keep_alive?
        break unless res.keep_alive?
      end
    end

    ##
    # Services +req+ and fills in +res+

    def service(mount_tab, req, res)
      if req.unparsed_uri == "*"
        if req.request_method == "OPTIONS"
          do_OPTIONS(req, res)
          raise HTTPStatus::OK
        end
        raise HTTPStatus::NotFound, "`#{req.unparsed_uri}' not found."
      end

      servlet, options, script_name, path_info = search_servlet(mount_tab, req.path)
      raise HTTPStatus::NotFound, "`#{req.path}' not found." unless servlet

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

    ##
    # Finds a servlet for +path+

    def search_servlet(mount_tab, path)
      script_name, path_info = mount_tab.scan(path)
      servlet, options = mount_tab[script_name]
      if servlet
        [servlet, options, script_name, path_info]
      end
    end

    ##
    # Logs +req+ and +res+ in the access logs.  +config+ is used for the
    # server name.

    def access_log(config, req, res)
      param = AccessLog.setup_params(config, req, res)
      config[:AccessLog].each { |fmt|
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
