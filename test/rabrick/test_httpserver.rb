# frozen_string_literal: false

require "test/unit"
require "net/http"
require "rabrick"
require_relative "utils"

class TestWEBrickHTTPServer < Test::Unit::TestCase
  empty_log = Object.new
  def empty_log.<<(str)
    assert_equal('', str)
    self
  end
  NoLog = Rabrick::Log.new(empty_log, Rabrick::BasicLog::WARN)

  def teardown
    Rabrick::Utils::TimeoutHandler.terminate
    super
  end

  class Req
    attr_reader :port, :host

    def initialize(addr, port, host)
      @addr = addr
      @port = port
      @host = host
    end

    def addr
      [0, 0, 0, @addr]
    end
  end

  def httpd(addr, port, host, ali)
    config = {
      :Logger => NoLog,
      :DoNotListen => true,
      :BindAddress => addr,
      :Port => port,
      :ServerName => host,
      :ServerAlias => ali
    }
    Rabrick::HTTPServer.new(config)
  end

  class CustomRequest < ::Rabrick::HTTPRequest; end
  class CustomResponse < ::Rabrick::HTTPResponse; end

  class CustomServer < ::Rabrick::HTTPServer
    def create_request(config)
      CustomRequest.new(config)
    end

    def create_response(config)
      CustomResponse.new(config)
    end
  end

  def test_custom_server_request_and_response
    omit

    config = { :ServerName => "localhost" }
    TestWEBrick.start_server(CustomServer, config) { |server, addr, port, _log|
      server.mount_proc("/", lambda { |req, res|
        assert_kind_of(CustomRequest, req)
        assert_kind_of(CustomResponse, res)
        res.body = "via custom response"
      })
      Thread.pass while server.status != :Running

      Net::HTTP.start(addr, port) do |http|
        req = Net::HTTP::Get.new("/")
        http.request(req) { |res|
          assert_equal("via custom response", res.body)
        }
        server.shutdown
      end
    }
  end

  # This class is needed by test_response_io_with_chunked_set method
  class EventManagerForChunkedResponseTest
    def initialize
      @listeners = []
    end

    def add_listener(&block)
      @listeners << block
    end

    def raise_str_event(str)
      @listeners.each { |e| e.call(:str, str) }
    end

    def raise_close_event
      @listeners.each { |e| e.call(:cls) }
    end
  end

  def test_response_io_with_chunked_set
    omit

    evt_man = EventManagerForChunkedResponseTest.new
    t = Thread.new do
      config = {
        :ServerName => "localhost"
      }
      TestWEBrick.start_httpserver(config) do |server, addr, port, _log|
        body_strs = %w[aaaaaa bb cccc]
        server.mount_proc("/", lambda { |_req, res|
          # Test for setting chunked...
          res.chunked = true
          r, w = IO.pipe
          evt_man.add_listener do |type, str|
            type == :cls ? w.close : (w << str)
          end
          res.body = r
        })
        Thread.pass while server.status != :Running
        http = Net::HTTP.new(addr, port)
        req  = Net::HTTP::Get.new("/")
        http.request(req) do |res|
          i = 0
          evt_man.raise_str_event(body_strs[i])
          res.read_body do |s|
            assert_equal(body_strs[i], s)
            i += 1
            if i < body_strs.length
              evt_man.raise_str_event(body_strs[i])
            else
              evt_man.raise_close_event()
            end
          end
          assert_equal(body_strs.length, i)
        end
      end
    rescue StandardError => e
      flunk('exception raised in thread: ' + e.to_s)
    end
    if t.join(3).nil?
      evt_man.raise_close_event()
      flunk('timeout')
      if t.join(1).nil?
        Thread.kill t
      end
    end
  end

  def test_response_io_without_chunked_set
    omit

    config = {
      :ServerName => "localhost"
    }
    log_tester = lambda { |log, _access_log|
      assert_empty log
    }
    TestWEBrick.start_httpserver(config, log_tester) { |server, addr, port, _log|
      server.mount_proc("/", lambda { |_req, res|
        r, w = IO.pipe
        # Test for not setting chunked...
        # res.chunked = true
        res.body = r
        w << "foo"
        w.close
      })
      Thread.pass while server.status != :Running
      http = Net::HTTP.new(addr, port)
      req = Net::HTTP::Get.new("/")
      req['Connection'] = 'Keep-Alive'
      begin
        Timeout.timeout(2) do
          http.request(req) { |res| assert_equal("foo", res.body) }
        end
      rescue Timeout::Error
        flunk('corrupted response')
      end
    }
  end

  def test_shutdown_with_busy_keepalive_connection
    omit

    requested = 0
    config = {
      :ServerName => "localhost"
    }
    TestWEBrick.start_httpserver(config) { |server, addr, port, log|
      server.mount_proc("/", ->(_req, res) { res.body = "heffalump" })
      Thread.pass while server.status != :Running

      Net::HTTP.start(addr, port) do |http|
        req = Net::HTTP::Get.new("/")
        http.request(req) { |res| assert_equal('Keep-Alive', res['Connection'], log.call) }
        server.shutdown
        begin
          10.times { |_n|
            http.request(req)
            requested += 1
          }
        rescue StandardError
          # Errno::ECONNREFUSED or similar
        end
      end
    }
    assert_equal(0, requested, "Server responded to #{requested} requests after shutdown")
  end

  def test_gigantic_request_header
    omit

    log_tester = lambda { |log, _access_log|
      assert_equal 1, log.size
      assert_include log[0], 'ERROR headers too large'
    }
    TestWEBrick.start_httpserver({}, log_tester) { |server, addr, port, _log|
      server.mount('/', Rabrick::HTTPServlet::FileHandler, __FILE__)
      TCPSocket.open(addr, port) do |c|
        c.write("GET / HTTP/1.0\r\n")
        junk = -"X-Junk: #{' ' * 1024}\r\n"
        assert_raise(Errno::ECONNRESET, Errno::EPIPE, Errno::EPROTOTYPE) do
          loop { c.write(junk) }
        end
      end
    }
  end

  def test_eof_in_chunk
    omit

    log_tester = lambda do |log, _access_log|
      assert_equal 1, log.size
      assert_include log[0], 'ERROR bad chunk data size'
    end
    TestWEBrick.start_httpserver({}, log_tester) { |server, addr, port, _log|
      server.mount_proc('/', ->(req, res) { res.body = req.body })
      TCPSocket.open(addr, port) do |c|
        c.write("POST / HTTP/1.1\r\nHost: example.com\r\n" \
                "Transfer-Encoding: chunked\r\n\r\n5\r\na")
        c.shutdown(Socket::SHUT_WR) # trigger EOF in server
        res = c.read
        assert_match %r{\AHTTP/1\.1 400 }, res
      end
    }
  end

  def test_big_chunks
    omit

    nr_out = 3
    buf = 'big' # 3 bytes is bigger than 2!
    config = { :InputBufferSize => 2 }.freeze
    total = 0
    all = ''
    TestWEBrick.start_httpserver(config) { |server, addr, port, _log|
      server.mount_proc('/', lambda { |req, res|
        err = []
        ret = req.body do |chunk|
          n = chunk.bytesize
          n > config[:InputBufferSize] and err << "#{n} > :InputBufferSize"
          total += n
          all << chunk
        end
        ret.nil? or err << 'req.body should return nil'
        (buf * nr_out) == all or err << 'input body does not match expected'
        res.header['connection'] = 'close'
        res.body = err.join("\n")
      })
      TCPSocket.open(addr, port) do |c|
        c.write("POST / HTTP/1.1\r\nHost: example.com\r\n" \
                "Transfer-Encoding: chunked\r\n\r\n")
        chunk = "#{buf.bytesize.to_s(16)}\r\n#{buf}\r\n"
        nr_out.times { c.write(chunk) }
        c.write("0\r\n\r\n")
        head, body = c.read.split("\r\n\r\n")
        assert_match %r{\AHTTP/1\.1 200 OK}, head
        assert_nil body
      end
    }
  end

  def test_accept_put_requests
    omit

    TestWEBrick.start_httpserver do |server, addr, port, _log|
      server.mount_proc("/", lambda { |req, res|
        res.status = 200
        assert_equal("abcde", req.body)
      })

      Thread.pass while server.status != :Running

      Net::HTTP.start(addr, port) do |http|
        req = Net::HTTP::Put.new("/")
        req.body = "abcde"
        req['content-type'] = "text/plain"

        http.request(req) do |res|
          assert_equal("200", res.code)
        end

        server.shutdown
      end
    end
  end
end
