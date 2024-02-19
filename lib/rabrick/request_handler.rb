# frozen_string_literal: true

require 'io/wait'
require_relative 'server'
require_relative 'httpstatus'
require_relative 'httprequest'
require_relative 'httpresponse'
require_relative 'accesslog'

module Rabrick
  module RequestHandler
    module_function

    ##
    # Processes requests on +sock+

    def run(config:, http_version:, sock:, status:, rack_app:)
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

          service(rack_app, req, res)
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

    def service(app, req, res)
      if req.unparsed_uri == "*"
        if req.request_method == "OPTIONS"
          do_OPTIONS(req, res)
          raise HTTPStatus::OK
        end
        raise HTTPStatus::NotFound, "`#{req.unparsed_uri}' not found."
      end

      env = req.meta_vars
      env.delete_if { |_k, v| v.nil? }

      input = req.body ? StringIO.new(req.body) : NullIO.new

      env.update(
        ::Rack::RACK_INPUT => input,
        ::Rack::RACK_ERRORS => $stderr,
        ::Rack::RACK_URL_SCHEME => "http", # XXX: rabrick does not support https at now.
        ::Rack::RACK_IS_HIJACK => true,
      )

      env[::Rack::QUERY_STRING] ||= ""
      unless env[::Rack::PATH_INFO] == ""
        path, n = req.request_uri.path, env[::Rack::SCRIPT_NAME].length
        env[::Rack::PATH_INFO] = path[n, path.length - n]
      end
      env[::Rack::REQUEST_PATH] ||= [env[::Rack::SCRIPT_NAME], env[::Rack::PATH_INFO]].join

      status, headers, body = app.call(env)

      begin
        res.status = status

        if value = headers[::Rack::RACK_HIJACK]
          io_lambda = value
          body = nil
        elsif !body.respond_to?(:to_path) && !body.respond_to?(:each)
          io_lambda = body
          body = nil
        end

        if value = headers.delete("set-cookie")
          res.cookies.concat(Array(value))
        end

        headers.each do |key, value|
          # Skip keys starting with rack., per Rack SPEC
          next if key.start_with?("rack.")

          # Since Rabrick won't accept repeated headers,
          # merge the values per RFC 1945 section 4.2.
          value = value.join(", ") if Array === value
          res[key] = value
        end

        if io_lambda
          protocol = headers["rack.protocol"] || headers["upgrade"]

          if protocol
            # Set all the headers correctly for an upgrade response:
            res.upgrade!(protocol)
          end
          res.body = io_lambda
        elsif body.respond_to?(:to_path)
          res.body = ::File.open(body.to_path, "rb")
        else
          buffer = String.new
          body.each do |part|
            buffer << part
          end
          res.body = buffer
        end
      ensure
        body.close if body.respond_to?(:close)
      end
    end

    ##
    # The default OPTIONS request handler says GET, HEAD, POST and OPTIONS
    # requests are allowed.

    def do_OPTIONS(_req, res)
      res["allow"] = "GET,HEAD,POST,OPTIONS"
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
