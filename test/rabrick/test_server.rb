# frozen_string_literal: false

require "test/unit"
require "tempfile"
require "rabrick"
require_relative "utils"

class TestWEBrickServer < Test::Unit::TestCase
  class Echo < Rabrick::GenericServer
    def run(sock)
      while line = sock.gets
        sock << line
      end
    end
  end

  def test_server
    TestWEBrick.start_server(Echo) { |_server, addr, port, log|
      TCPSocket.open(addr, port) { |sock|
        sock.puts("foo")
        assert_equal("foo\n", sock.gets, log.call)
        sock.puts("bar")
        assert_equal("bar\n", sock.gets, log.call)
        sock.puts("baz")
        assert_equal("baz\n", sock.gets, log.call)
        sock.puts("qux")
        assert_equal("qux\n", sock.gets, log.call)
      }
    }
  end

  def test_start_exception
    omit

    stopped = 0

    log = []
    logger = Rabrick::Log.new(log, Rabrick::BasicLog::WARN)

    assert_raise(SignalException) do
      listener = Object.new
      def listener.to_io # IO.select invokes #to_io.
        raise SignalException, 'SIGTERM' # simulate signal in main thread
      end

      def listener.shutdown
      end

      def listener.close
      end

      server = Rabrick::HTTPServer.new({
        :BindAddress => "127.0.0.1", :Port => 0,
        :Logger => logger
      })
      server.listeners[0].close
      server.listeners[0] = listener

      server.start
    end

    assert_equal(1, stopped)
    assert_equal(1, log.length)
    assert_match(/FATAL SignalException: SIGTERM/, log[0])
  end

  def test_daemon
    r, w = IO.pipe
    pid1 = Process.fork {
      r.close
      Rabrick::Daemon.start
      w.puts(Process.pid)
      sleep 10
    }
    pid2 = r.gets.to_i
    assert(Process.kill(:KILL, pid2))
    assert_not_equal(pid1, pid2)
  rescue NotImplementedError
    # snip this test
  ensure
    Process.wait(pid1) if pid1
    r.close
    w.close
  end

  def test_restart_after_shutdown
    address = '127.0.0.1'
    port = 0
    log = []
    config = {
      :BindAddress => address,
      :Port => port,
      :Logger => Rabrick::Log.new(log, Rabrick::BasicLog::WARN)
    }
    server = Echo.new(config)
    client_proc = lambda { |str|
      begin
        ret = server.listeners.first.connect_address.connect { |s|
          s.write(str)
          s.close_write
          s.read
        }
        assert_equal(str, ret)
      ensure
        server.shutdown
      end
    }
    server_thread = Thread.new { server.start }
    client_thread = Thread.new { client_proc.call("a") }
    assert_join_threads([client_thread, server_thread])
    server.listen(address, port)
    server_thread = Thread.new { server.start }
    client_thread = Thread.new { client_proc.call("b") }
    assert_join_threads([client_thread, server_thread])
    assert_equal([], log)
  end

  def test_restart_after_stop
    log = Object.new
    class << log
      include Test::Unit::Assertions
      def <<(msg)
        flunk "unexpected log: #{msg.inspect}"
      end
    end
    client_thread = nil
    wakeup = -> { client_thread.wakeup }
    warn_flunk = Rabrick::Log.new(log, Rabrick::BasicLog::WARN)
    server = Rabrick::HTTPServer.new(
      :BindAddress => '0.0.0.0',
      :Port => 0,
      :Logger => warn_flunk
    )
    2.times {
      server_thread = Thread.start {
        server.start
      }
      client_thread = Thread.start {
        sleep 0.1 until server.status == :Running || !server_thread.status
        server.stop
        sleep 0.1 until server.status == :Stop || !server_thread.status
      }
      assert_join_threads([client_thread, server_thread])
    }
  end

  def test_port_numbers
    config = {
      :BindAddress => '0.0.0.0',
      :Logger => Rabrick::Log.new([], Rabrick::BasicLog::WARN)
    }

    ports = [0, "0"]

    ports.each do |port|
      config[:Port] = port
      server = Rabrick::GenericServer.new(config)
      server_thread = Thread.start { server.start }
      client_thread = Thread.start {
        sleep 0.1 until server.status == :Running || !server_thread.status
        server_port = server.listeners[0].addr[1]
        server.stop
        assert_equal server.config[:Port], server_port
        sleep 0.1 until server.status == :Stop || !server_thread.status
      }
      assert_join_threads([client_thread, server_thread])
    end

    assert_raise(ArgumentError) do
      config[:Port] = "FOO"
      Rabrick::GenericServer.new(config)
    end
  end
end
