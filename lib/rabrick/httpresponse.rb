# frozen_string_literal: true

#
# httpresponse.rb -- HTTPResponse Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httpresponse.rb,v 1.45 2003/07/11 11:02:25 gotoyuzo Exp $

require 'time'
require 'uri'
require_relative 'httpversion'
require_relative 'htmlutils'
require_relative 'httputils'
require_relative 'httpstatus'

module Rabrick
  ##
  # An HTTP response.  This is filled in by the service or do_* methods of a
  # Rabrick HTTP Servlet.

  class HTTPResponse
    class InvalidHeader < StandardError
    end

    ##
    # HTTP Response version

    attr_reader :http_version, :status, :header, :cookies, :config, :sent_size

    ##
    # Response status code (200)

    ##
    # Response header

    ##
    # Response cookies

    ##
    # Response reason phrase ("OK")

    attr_accessor :reason_phrase, :body, :request_method, :request_uri, :request_http_version, :filename, :keep_alive, :upgrade

    ##
    # Body may be:
    # * a String;
    # * an IO-like object that responds to +#read+ and +#readpartial+;
    # * a Proc-like object that responds to +#call+.
    #
    # In the latter case, either #chunked= should be set to +true+,
    # or <code>header['content-length']</code> explicitly provided.
    # Example:
    #
    #   server.mount_proc '/' do |req, res|
    #     res.chunked = true
    #     # or
    #     # res.header['content-length'] = 10
    #     res.body = proc { |out| out.write(Time.now.to_s) }
    #   end

    ##
    # Request method for this response

    ##
    # Request URI for this response

    ##
    # Request HTTP version for this response

    ##
    # Filename of the static file in this response.  Only used by the
    # FileHandler servlet.

    ##
    # Is this a keep-alive response?

    ##
    # Configuration for this response

    ##
    # Bytes sent in this response

    ##
    # Set the response body proc as an streaming/upgrade response.

    ##
    # Creates a new HTTP response object.  Rabrick::Config::HTTP is the
    # default configuration.

    def initialize(config)
      @config = config
      @config[:ServerName] # Touch to load default value
      @config = Rabrick::Config.make_shareable(@config)
      @buffer_size = config[:OutputBufferSize]
      @header = {}
      @status = HTTPStatus::RC_OK
      @reason_phrase = nil
      @http_version = HTTPVersion.convert(@config[:HTTPVersion])
      @body = +""
      @keep_alive = true
      @cookies = []
      @request_method = nil
      @request_uri = nil
      @request_http_version = @http_version # temporary
      @chunked = false
      @filename = nil
      @sent_size = 0
      @bodytempfile = nil
    end

    ##
    # The response's HTTP status line

    def status_line
      "HTTP/#{@http_version} #{@status} #{@reason_phrase}".rstrip << CRLF
    end

    ##
    # Sets the response's status to the +status+ code

    def status=(status)
      @status = status
      @reason_phrase = HTTPStatus.reason_phrase(status)
    end

    ##
    # Retrieves the response header +field+

    def [](field)
      @header[field.downcase]
    end

    ##
    # Sets the response header +field+ to +value+

    def []=(field, value)
      @chunked = value.to_s.downcase == 'chunked' if field.downcase == 'transfer-encoding'
      @header[field.downcase] = value.to_s
    end

    ##
    # The content-length header

    def content_length
      if len = self['content-length']
        Integer(len)
      end
    end

    ##
    # Sets the content-length header to +len+

    def content_length=(len)
      self['content-length'] = len.to_s
    end

    ##
    # The content-type header

    def content_type
      self['content-type']
    end

    ##
    # Sets the content-type header to +type+

    def content_type=(type)
      self['content-type'] = type
    end

    ##
    # Iterates over each header in the response

    def each(&block)
      @header.each(&block)
    end

    ##
    # Will this response body be returned using chunked transfer-encoding?

    def chunked?
      @chunked
    end

    ##
    # Enables chunked transfer encoding.

    def chunked=(val)
      @chunked = val ? true : false
    end

    ##
    # Will this response's connection be kept alive?

    def keep_alive?
      @keep_alive
    end

    ##
    # Sets the response to be a streaming/upgrade response.
    # This will disable keep-alive and chunked transfer encoding.

    def upgrade!(protocol)
      @upgrade = protocol
      @keep_alive = false
      @chunked = false
    end

    ##
    # Sends the response on +socket+

    def send_response(socket) # :nodoc:
      setup_header()
      send_header(socket)
      send_body(socket)
    rescue Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN => e
      Rabrick::RactorLogger.debug(e)
      @keep_alive = false
    rescue Exception => e
      Rabrick::RactorLogger.error(e)
      @keep_alive = false
    end

    ##
    # Sets up the headers for sending

    def setup_header # :nodoc:
      @reason_phrase    ||= HTTPStatus.reason_phrase(@status)
      @header['server'] ||= @config[:ServerSoftware]
      @header['date']   ||= Time.now.httpdate

      if @upgrade
        @header['connection'] = 'upgrade'
        @header['upgrade'] = @upgrade
        @keep_alive = false

        return
      end

      # HTTP/0.9 features
      if @request_http_version < "1.0"
        @http_version = HTTPVersion.new("0.9")
        @keep_alive = false
      end

      # HTTP/1.0 features
      if @request_http_version < "1.1" && chunked?
        @chunked = false
        ver = @request_http_version.to_s
        msg = "chunked is set for an HTTP/#{ver} request. (ignored)"
        Rabrick::RactorLogger.warn(msg)
      end

      # Determine the message length (RFC2616 -- 4.4 Message Length)
      if @status == 304 || @status == 204 || HTTPStatus.info?(@status)
        @header.delete('content-length')
        @body = ""
      elsif chunked?
        @header["transfer-encoding"] = "chunked"
        @header.delete('content-length')
      elsif %r{^multipart/byteranges} =~ @header['content-type']
        @header.delete('content-length')
      elsif @header['content-length'].nil?
        if @body.respond_to?(:bytesize)
          @header['content-length'] = @body.bytesize.to_s
        else
          @header['connection'] = 'close'
        end
      end

      # Keep-Alive connection.
      if @header['connection'] == "close"
        @keep_alive = false
      elsif keep_alive?
        if chunked? || @header['content-length'] || @status == 304 || @status == 204 || HTTPStatus.info?(@status)
          @header['connection'] = "Keep-Alive"
        else
          msg = "Could not determine content-length of response body. Set content-length of the response or set Response#chunked = true"
          Rabrick::RactorLogger.warn(msg)
          @header['connection'] = "close"
          @keep_alive = false
        end
      else
        @header['connection'] = "close"
      end

      # Location is a single absoluteURI.
      if (location = @header['location']) && @request_uri
        @header['location'] = @request_uri.merge(location).to_s
      end
    end

    def make_body_tempfile # :nodoc:
      return if @bodytempfile

      bodytempfile = Tempfile.create("rabrick")
      if @body.nil?
        # nothing
      elsif @body.respond_to? :readpartial
        IO.copy_stream(@body, bodytempfile)
        @body.close
      elsif @body.respond_to? :call
        @body.call(bodytempfile)
      else
        bodytempfile.write @body
      end
      bodytempfile.rewind
      @body = @bodytempfile = bodytempfile
      @header['content-length'] = bodytempfile.stat.size.to_s
    end

    def remove_body_tempfile # :nodoc:
      if @bodytempfile
        @bodytempfile.close
        File.unlink @bodytempfile.path
        @bodytempfile = nil
      end
    end

    ##
    # Sends the headers on +socket+

    def send_header(socket) # :nodoc:
      if @http_version.major > 0
        data = status_line().dup
        @header.each { |key, value|
          tmp = key.gsub(/\bwww|^te$|\b\w/) { ::Regexp.last_match(0).upcase }
          data << "#{tmp}: #{check_header(value)}" << CRLF
        }
        @cookies.each { |cookie|
          data << "Set-Cookie: " << check_header(cookie.to_s) << CRLF
        }
        data << CRLF
        socket.write(data)
      end
    rescue InvalidHeader => e
      @header.clear
      @cookies.clear
      set_error e
      retry
    end

    ##
    # Sends the body on +socket+

    def send_body(socket) # :nodoc:
      if @body.respond_to? :readpartial
        send_body_io(socket)
      elsif @body.respond_to?(:call)
        send_body_proc(socket)
      else
        send_body_string(socket)
      end
    end

    ##
    # Redirects to +url+ with a Rabrick::HTTPStatus::Redirect +status+.
    #
    # Example:
    #
    #   res.set_redirect Rabrick::HTTPStatus::TemporaryRedirect

    def set_redirect(status, url)
      url = URI(url).to_s
      @body = "<HTML><A HREF=\"#{url}\">#{url}</A>.</HTML>\n"
      @header['location'] = url
      raise status
    end

    ##
    # Creates an error page for exception +ex+ with an optional +backtrace+

    def set_error(ex, backtrace = false)
      case ex
      when HTTPStatus::Status
        @keep_alive = false if HTTPStatus.error?(ex.code)
        self.status = ex.code
      else
        @keep_alive = false
        self.status = HTTPStatus::RC_INTERNAL_SERVER_ERROR
      end
      @header['content-type'] = "text/html; charset=ISO-8859-1"

      if respond_to?(:create_error_page)
        create_error_page()
        return
      end

      if @request_uri
        host = @request_uri.host
        port = @request_uri.port
      else
        host = @config[:ServerName]
        port = @config[:Port]
      end

      error_body(backtrace, ex, host, port)
    end

    private

    def check_header(header_value)
      header_value = header_value.to_s
      if /[\r\n]/ =~ header_value
        raise InvalidHeader
      else
        header_value
      end
    end

    # :stopdoc:

    def error_body(backtrace, ex, host, port)
      @body = +""
      @body << <<~_END_OF_HTML_
        <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN">
        <HTML>
          <HEAD><TITLE>#{HTMLUtils.escape(@reason_phrase)}</TITLE></HEAD>
          <BODY>
            <H1>#{HTMLUtils.escape(@reason_phrase)}</H1>
            #{HTMLUtils.escape(ex.message)}
            <HR>
      _END_OF_HTML_

      if backtrace && $DEBUG
        @body << "backtrace of `#{HTMLUtils.escape(ex.class.to_s)}' "
        @body << "#{HTMLUtils.escape(ex.message)}"
        @body << "<PRE>"
        ex.backtrace.each { |line| @body << "\t#{line}\n" }
        @body << "</PRE><HR>"
      end

      @body << <<~_END_OF_HTML_
            <ADDRESS>
             #{HTMLUtils.escape(@config[:ServerSoftware])} at
             #{host}:#{port}
            </ADDRESS>
          </BODY>
        </HTML>
      _END_OF_HTML_
    end

    def send_body_io(socket)
      begin
        if @request_method == "HEAD"
          # do nothing
        elsif chunked?
          buf = +''
          begin
            @body.readpartial(@buffer_size, buf)
            size = buf.bytesize
            data = +"#{size.to_s(16)}#{CRLF}#{buf}#{CRLF}"
            socket.write(data)
            data.clear
            @sent_size += size
          rescue EOFError
            break
          end while true
          buf.clear
          socket.write("0#{CRLF}#{CRLF}")
        else
          if %r{\Abytes (\d+)-(\d+)/\d+\z} =~ @header['content-range']
            offset = ::Regexp.last_match(1).to_i
            size = ::Regexp.last_match(2).to_i - offset + 1
          else
            offset = nil
            size = @header['content-length']
            size = size.to_i if size
          end
          begin
            @sent_size = IO.copy_stream(@body, socket, size, offset)
          rescue NotImplementedError
            @body.seek(offset, IO::SEEK_SET)
            @sent_size = IO.copy_stream(@body, socket, size)
          end
        end
      ensure
        @body.close
      end
      remove_body_tempfile
    end

    def send_body_string(socket)
      if @request_method == "HEAD"
        # do nothing
      elsif chunked?
        body ? @body.bytesize : 0
        while buf = @body[@sent_size, @buffer_size]
          break if buf.empty?

          size = buf.bytesize
          data = "#{size.to_s(16)}#{CRLF}#{buf}#{CRLF}"
          buf.clear
          socket.write(data)
          @sent_size += size
        end
        socket.write("0#{CRLF}#{CRLF}")
      elsif @body && @body.bytesize > 0
        socket.write(@body)
        @sent_size = @body.bytesize
      end
    end

    def send_body_proc(socket)
      if @request_method == "HEAD"
        # do nothing
      elsif chunked?
        @body.call(ChunkedWrapper.new(socket, self))
        socket.write("0#{CRLF}#{CRLF}")
      else
        if @bodytempfile
          @bodytempfile.rewind
          IO.copy_stream(@bodytempfile, socket)
        else
          @body.call(socket)
        end

        if content_length = @header['content-length']
          @sent_size = content_length.to_i
        end
      end
    end

    class ChunkedWrapper
      def initialize(socket, resp)
        @socket = socket
        @resp = resp
      end

      def write(buf)
        return 0 if buf.empty?

        socket = @socket
        @resp.instance_eval {
          size = buf.bytesize
          data = +"#{size.to_s(16)}#{CRLF}#{buf}#{CRLF}"
          socket.write(data)
          data.clear
          @sent_size += size
          size
        }
      end

      def <<(*buf)
        write(buf)
        self
      end
    end

    # preserved for compatibility with some 3rd-party handlers
    def _write_data(socket, data)
      socket << data
    end

    # :startdoc:
  end
end
