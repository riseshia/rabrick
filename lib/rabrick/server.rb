# frozen_string_literal: true

#
# server.rb -- GenericServer Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: server.rb,v 1.62 2003/07/22 19:20:43 gotoyuzo Exp $

require 'socket'
require_relative 'config'
require_relative 'log'
require_relative 'request_handler'

module Rabrick
  ##
  # Server error exception

  class ServerError < StandardError; end

  ##
  # Base server class

  class SimpleServer
    ##
    # A SimpleServer only yields when you start it

    def self.start
      yield
    end
  end

  ##
  # A generic module for daemonizing a process

  class Daemon
    ##
    # Performs the standard operations for daemonizing a process.  Runs a
    # block, if given.

    def self.start
      Process.daemon
      File.umask(0)
      yield if block_given?
    end
  end

  ##
  # Base TCP server class.  You must subclass GenericServer and provide a #run
  # method.

  class GenericServer
    ##
    # The server status.  One of :Stop, :Running or :Shutdown

    attr_reader :status, :config, :logger, :tokens, :listeners

    ##
    # The server configuration

    ##
    # The server logger.  This is independent from the HTTP access log.

    ##
    # Tokens control the number of outstanding clients.  The
    # <code>:MaxClients</code> configuration sets this.

    ##
    # Sockets listening for connections.

    ##
    # Creates a new generic server from +config+.  The default configuration
    # comes from +default+.

    def initialize(config = {}, default = Config::General)
      @config = default.dup.update(config)
      @status = :Stop

      @tokens = Thread::SizedQueue.new(@config[:MaxClients])
      @config[:MaxClients].times { @tokens.push(nil) }

      rabrickv = Rabrick::VERSION
      rubyv = "#{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"
      Rabrick::RactorLogger.info("Rabrick #{rabrickv}")
      Rabrick::RactorLogger.info("ruby #{rubyv}")

      @listeners = []
      @shutdown_pipe = nil
      unless @config[:DoNotListen]
        raise ArgumentError, "Port must be an integer" unless @config[:Port].to_s == @config[:Port].to_i.to_s

        @config[:Port] = @config[:Port].to_i
        if @config[:Listen]
          warn(":Listen option is deprecated; use GenericServer#listen", uplevel: 1)
        end
        listen(@config[:BindAddress], @config[:Port])
        if @config[:Port] == 0
          @config[:Port] = @listeners[0].addr[1]
        end
      end
    end

    ##
    # Retrieves +key+ from the configuration

    def [](key)
      @config[key]
    end

    ##
    # Adds listeners from +address+ and +port+ to the server.  See
    # Rabrick::Utils::create_listeners for details.

    def listen(address, port)
      @listeners += Utils.create_listeners(address, port)
    end

    ##
    # Starts the server and runs the +block+ for each connection.  This method
    # does not return until the server is stopped from a signal handler or
    # another thread using #stop or #shutdown.
    #
    # If the block raises a subclass of StandardError the exception is logged
    # and ignored.  If an IOError or Errno::EBADF exception is raised the
    # exception is ignored.  If an Exception subclass is raised the exception
    # is logged and re-raised which stops the server.
    #
    # To completely shut down a server call #shutdown from ensure:
    #
    #   server = Rabrick::GenericServer.new
    #   # or Rabrick::HTTPServer.new
    #
    #   begin
    #     server.start
    #   ensure
    #     server.shutdown
    #   end

    def start
      raise ServerError, "already started." if @status != :Stop

      server_type = @config[:ServerType] || SimpleServer

      setup_shutdown_pipe

      server_type.start {
        Rabrick::RactorLogger.info \
          "#{self.class}#start: pid=#{$$} port=#{@config[:Port]}"
        @status = :Running

        shutdown_pipe = @shutdown_pipe

        begin
          while @status == :Running
            begin
              sp = shutdown_pipe[0]
              if svrs = IO.select([sp, *@listeners])
                if svrs[0].include? sp
                  # swallow shutdown pipe
                  buf = String.new
                  nil while sp.read_nonblock([sp.nread, 8].max, buf, exception: false).is_a?(String)
                  break
                end
                svrs[0].each { |svr|
                  @tokens.pop # blocks while no token is there.
                  if sock = accept_client(svr)
                    unless config[:DoNotReverseLookup].nil?
                      sock.do_not_reverse_lookup = !!config[:DoNotReverseLookup]
                    end
                    start_ractor(sock)
                  else
                    @tokens.push(nil)
                  end
                }
              end
            rescue Errno::EBADF, Errno::ENOTSOCK, IOError => e
              # if the listening socket was closed in GenericServer#shutdown,
              # IO::select raise it.
            rescue StandardError => e
              msg = "#{e.class}: #{e.message}\n\t#{e.backtrace[0]}"
              Rabrick::RactorLogger.error msg
            rescue Exception => e
              Rabrick::RactorLogger.fatal e
              raise
            end
          end
        ensure
          cleanup_shutdown_pipe(shutdown_pipe)
          cleanup_listener
          @status = :Shutdown
          Rabrick::RactorLogger.info "going to shutdown ..."
          Rabrick::RactorLogger.info "#{self.class}#start done."
          @status = :Stop
        end
      }
    end

    ##
    # Stops the server from accepting new connections.

    def stop
      if @status == :Running
        @status = :Shutdown
      end

      alarm_shutdown_pipe { |f| f.write_nonblock("\0") }
    end

    ##
    # Shuts down the server and all listening sockets.  New listeners must be
    # provided to restart the server.

    def shutdown
      stop

      alarm_shutdown_pipe(&:close)
    end

    ##
    # You must subclass GenericServer and implement \#run which accepts a TCP
    # client socket

    def run(_sock)
      Rabrick::RactorLogger.fatal "run() must be provided by user."
    end

    private

    # :stopdoc:

    ##
    # Accepts a TCP client socket from the TCP server socket +svr+ and returns
    # the client socket.

    def accept_client(svr)
      case sock = svr.to_io.accept_nonblock(exception: false)
      when :wait_readable
        nil
      else
        sock
      end
    rescue Errno::ECONNRESET, Errno::ECONNABORTED,
           Errno::EPROTO, Errno::EINVAL
      nil
    rescue StandardError => e
      msg = "#{e.class}: #{e.message}\n\t#{e.backtrace[0]}"
      Rabrick::RactorLogger.error msg
      nil
    end

    ##
    # Starts a server thread for the client socket +sock+ that runs the given
    # +block+.
    #
    # Sets the socket to the <code>:WEBrickSocket</code> thread local variable
    # in the thread.
    #
    # If any errors occur in the block they are logged and handled.

    def start_ractor(sock)
      Thread.start {
        begin
          Thread.current[:WEBrickSocket] = sock
          begin
            addr = sock.peeraddr
            Rabrick::RactorLogger.debug "accept: #{addr[3]}:#{addr[1]}"
          rescue SocketError
            Rabrick::RactorLogger.debug "accept: <address unknown>"
            raise
          end
          run(sock)
        rescue Errno::ENOTCONN
          Rabrick::RactorLogger.debug "Errno::ENOTCONN raised"
        rescue ServerError => e
          msg = "#{e.class}: #{e.message}\n\t#{e.backtrace[0]}"
          Rabrick::RactorLogger.error msg
        rescue Exception => e
          Rabrick::RactorLogger.error e
        ensure
          @tokens.push(nil)
          Thread.current[:WEBrickSocket] = nil
          if addr
            Rabrick::RactorLogger.debug "close: #{addr[3]}:#{addr[1]}"
          else
            Rabrick::RactorLogger.debug "close: <address unknown>"
          end
          sock.close
        end
      }
    end

    def setup_shutdown_pipe
      @shutdown_pipe ||= IO.pipe
    end

    def cleanup_shutdown_pipe(shutdown_pipe)
      @shutdown_pipe = nil
      shutdown_pipe&.each(&:close)
    end

    def alarm_shutdown_pipe
      _, pipe = @shutdown_pipe # another thread may modify @shutdown_pipe.
      if pipe && !pipe.closed?
        begin
          yield pipe
        rescue IOError # closed by another thread.
        end
      end
    end

    def cleanup_listener
      @listeners.each { |s|
        if Rabrick::RactorLogger.debug?
          addr = s.addr
          Rabrick::RactorLogger.debug("close TCPSocket(#{addr[2]}, #{addr[1]})")
        end
        begin
          s.shutdown
        rescue Errno::ENOTCONN
          # when `Errno::ENOTCONN: Socket is not connected' on some platforms,
          # call #close instead of #shutdown.
          # (ignore @config[:ShutdownSocketWithoutClose])
          s.close
        else
          unless @config[:ShutdownSocketWithoutClose]
            s.close
          end
        end
      }
      @listeners.clear
    end
  end # end of GenericServer
end
