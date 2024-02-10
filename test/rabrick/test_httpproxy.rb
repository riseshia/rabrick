# frozen_string_literal: false

require "test/unit"
require "net/http"
require "rabrick"
require "rabrick/httpproxy"
begin
  require "rabrick/ssl"
  require "net/https"
rescue LoadError
  # test_connect will be skipped
end
require File.expand_path("utils.rb", File.dirname(__FILE__))

class TestWEBrickHTTPProxy < Test::Unit::TestCase
  def teardown
    Rabrick::Utils::TimeoutHandler.terminate
    super
  end

  def test_fake_proxy
    assert_nil(Rabrick::FakeProxyURI.scheme)
    assert_nil(Rabrick::FakeProxyURI.host)
    assert_nil(Rabrick::FakeProxyURI.port)
    assert_nil(Rabrick::FakeProxyURI.path)
    assert_nil(Rabrick::FakeProxyURI.userinfo)
    assert_raise(NoMethodError) { Rabrick::FakeProxyURI.foo }
  end

  def test_proxy
    omit

    # Testing GET or POST to the proxy server
    # Note that the proxy server works as the origin server.
    #                    +------+
    #                    V      |
    #  client -------> proxy ---+
    #        GET / POST     GET / POST
    #
    proxy_handler_called = request_handler_called = 0
    config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => proc { |_req, _res| proxy_handler_called += 1 }
    }
    TestWEBrick.start_httpproxy(config) { |server, addr, port, log|
      server.mount_proc("/") { |req, res|
        res.body = "#{req.request_method} #{req.path} #{req.body}"
      }
      http = Net::HTTP.new(addr, port, addr, port)

      req = Net::HTTP::Get.new("/")
      http.request(req) { |res|
        assert_equal("1.1 localhost.localdomain:#{port}", res["via"], log.call)
        assert_equal("GET / ", res.body, log.call)
      }
      assert_equal(1, proxy_handler_called, log.call)
      assert_equal(2, request_handler_called, log.call)

      req = Net::HTTP::Head.new("/")
      http.request(req) { |res|
        assert_equal("1.1 localhost.localdomain:#{port}", res["via"], log.call)
        assert_nil(res.body, log.call)
      }
      assert_equal(2, proxy_handler_called, log.call)
      assert_equal(4, request_handler_called, log.call)

      req = Net::HTTP::Post.new("/")
      req.body = "post-data"
      req.content_type = "application/x-www-form-urlencoded"
      http.request(req) { |res|
        assert_equal("1.1 localhost.localdomain:#{port}", res["via"], log.call)
        assert_equal("POST / post-data", res.body, log.call)
      }
      assert_equal(3, proxy_handler_called, log.call)
      assert_equal(6, request_handler_called, log.call)
    }
  end

  def test_no_proxy
    omit

    # Testing GET or POST to the proxy server without proxy request.
    #
    #  client -------> proxy
    #        GET / POST
    #
    proxy_handler_called = request_handler_called = 0
    config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => proc { |_req, _res| proxy_handler_called += 1 }
    }
    TestWEBrick.start_httpproxy(config) { |server, addr, port, log|
      server.mount_proc("/") { |req, res|
        res.body = "#{req.request_method} #{req.path} #{req.body}"
      }
      http = Net::HTTP.new(addr, port)

      req = Net::HTTP::Get.new("/")
      http.request(req) { |res|
        assert_nil(res["via"], log.call)
        assert_equal("GET / ", res.body, log.call)
      }
      assert_equal(0, proxy_handler_called, log.call)
      assert_equal(1, request_handler_called, log.call)

      req = Net::HTTP::Head.new("/")
      http.request(req) { |res|
        assert_nil(res["via"], log.call)
        assert_nil(res.body, log.call)
      }
      assert_equal(0, proxy_handler_called, log.call)
      assert_equal(2, request_handler_called, log.call)

      req = Net::HTTP::Post.new("/")
      req.content_type = "application/x-www-form-urlencoded"
      req.body = "post-data"
      http.request(req) { |res|
        assert_nil(res["via"], log.call)
        assert_equal("POST / post-data", res.body, log.call)
      }
      assert_equal(0, proxy_handler_called, log.call)
      assert_equal(3, request_handler_called, log.call)
    }
  end

  if RUBY_VERSION >= '2.5'
    def test_big_bodies
      omit

      require 'digest/md5'
      rand_str = File.read(__FILE__)
      rand_str.freeze
      nr = 1024**2 / rand_str.size # bigger works, too
      exp = Digest::MD5.new
      nr.times { exp.update(rand_str) }
      exp = exp.hexdigest
      TestWEBrick.start_httpserver do |o_server, o_addr, o_port, _o_log|
        o_server.mount_proc('/') do |req, res|
          case req.request_method
          when 'GET'
            res['content-type'] = 'application/octet-stream'
            if req.path == '/length'
              res['content-length'] = (nr * rand_str.size).to_s
            else
              res.chunked = true
            end
            res.body = ->(socket) { nr.times { socket.write(rand_str) } }
          when 'POST'
            dig = Digest::MD5.new
            req.body { |buf|
              dig.update(buf)
              buf.clear
            }
            res['content-type'] = 'text/plain'
            res['content-length'] = '32'
            res.body = dig.hexdigest
          end
        end

        http = Net::HTTP.new(o_addr, o_port)
        IO.pipe do |rd, wr|
          headers = {
            'Content-Type' => 'application/octet-stream',
            'Transfer-Encoding' => 'chunked'
          }
          post = Net::HTTP::Post.new('/', headers)
          th = Thread.new {
            nr.times { wr.write(rand_str) }
            wr.close
          }
          post.body_stream = rd
          http.request(post) do |res|
            assert_equal 'text/plain', res['content-type']
            assert_equal 32, res.content_length
            assert_equal exp, res.body
          end
          assert_nil th.value
        end

        TestWEBrick.start_httpproxy do |_p_server, p_addr, p_port, _p_log|
          http = Net::HTTP.new(o_addr, o_port, p_addr, p_port)
          http.request_get('/length') do |res|
            assert_equal(nr * rand_str.size, res.content_length)
            dig = Digest::MD5.new
            res.read_body { |buf|
              dig.update(buf)
              buf.clear
            }
            assert_equal exp, dig.hexdigest
          end
          http.request_get('/') do |res|
            assert_predicate res, :chunked?
            dig = Digest::MD5.new
            res.read_body { |buf|
              dig.update(buf)
              buf.clear
            }
            assert_equal exp, dig.hexdigest
          end

          IO.pipe do |rd, wr|
            headers = {
              'Content-Type' => 'application/octet-stream',
              'Content-Length' => (nr * rand_str.size).to_s
            }
            post = Net::HTTP::Post.new('/', headers)
            th = Thread.new {
              nr.times { wr.write(rand_str) }
              wr.close
            }
            post.body_stream = rd
            http.request(post) do |res|
              assert_equal 'text/plain', res['content-type']
              assert_equal 32, res.content_length
              assert_equal exp, res.body
            end
            assert_nil th.value
          end

          IO.pipe do |rd, wr|
            headers = {
              'Content-Type' => 'application/octet-stream',
              'Transfer-Encoding' => 'chunked'
            }
            post = Net::HTTP::Post.new('/', headers)
            th = Thread.new {
              nr.times { wr.write(rand_str) }
              wr.close
            }
            post.body_stream = rd
            http.request(post) do |res|
              assert_equal 'text/plain', res['content-type']
              assert_equal 32, res.content_length
              assert_equal exp, res.body
            end
            assert_nil th.value
          end
        end
      end
    end
  end

  def test_http10_proxy_chunked
    omit

    # Testing HTTP/1.0 client request and HTTP/1.1 chunked response
    # from origin server.
    #                    +------+
    #                    V      |
    #  client -------> proxy ---+
    #           GET          GET
    #           HTTP/1.0     HTTP/1.1
    #           non-chunked  chunked
    #
    proxy_handler_called = request_handler_called = 0
    config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => proc { |_req, _res| proxy_handler_called += 1 }
    }
    log_tester = lambda { |log, _access_log|
      log.reject! { |str|
        %r{WARN  chunked is set for an HTTP/1\.0 request\. \(ignored\)} =~ str
      }
      assert_equal([], log)
    }
    TestWEBrick.start_httpproxy(config, log_tester) { |server, addr, port, _log|
      body = nil
      server.mount_proc("/") { |req, res|
        body = "#{req.request_method} #{req.path} #{req.body}"
        res.chunked = true
        res.body = ->(socket) { body.each_char { |c| socket.write c } }
      }

      # Don't use Net::HTTP because it uses HTTP/1.1.
      TCPSocket.open(addr, port) { |s|
        s.write "GET / HTTP/1.0\r\nHost: localhost.localdomain\r\n\r\n"
        response = s.read
        assert_equal(body, response[/.*\z/])
      }
    }
  end

  def test_upstream_proxy
    omit

    # Testing GET or POST through the upstream proxy server
    # Note that the upstream proxy server works as the origin server.
    #                                   +------+
    #                                   V      |
    #  client -------> proxy -------> proxy ---+
    #        GET / POST     GET / POST     GET / POST
    #
    up_proxy_handler_called = up_request_handler_called = 0
    proxy_handler_called = request_handler_called = 0
    up_config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => proc { |_req, _res| up_proxy_handler_called += 1 }
    }
    TestWEBrick.start_httpproxy(up_config) { |up_server, up_addr, up_port, up_log|
      up_server.mount_proc("/") { |req, res|
        res.body = "#{req.request_method} #{req.path} #{req.body}"
      }
      config = {
        :ServerName => "localhost.localdomain",
        :ProxyURI => URI.parse("http://localhost:#{up_port}"),
        :ProxyContentHandler => proc { |_req, _res| proxy_handler_called += 1 }
      }
      TestWEBrick.start_httpproxy(config) { |_server, addr, port, log|
        http = Net::HTTP.new(up_addr, up_port, addr, port)

        req = Net::HTTP::Get.new("/")
        http.request(req) { |res|
          skip res.message unless res.code == '200'
          via = res["via"].split(/,\s+/)
          assert(via.include?("1.1 localhost.localdomain:#{up_port}"), up_log.call + log.call)
          assert(via.include?("1.1 localhost.localdomain:#{port}"), up_log.call + log.call)
          assert_equal("GET / ", res.body)
        }
        assert_equal(1, up_proxy_handler_called, up_log.call + log.call)
        assert_equal(2, up_request_handler_called, up_log.call + log.call)
        assert_equal(1, proxy_handler_called, up_log.call + log.call)
        assert_equal(1, request_handler_called, up_log.call + log.call)

        req = Net::HTTP::Head.new("/")
        http.request(req) { |res|
          via = res["via"].split(/,\s+/)
          assert(via.include?("1.1 localhost.localdomain:#{up_port}"), up_log.call + log.call)
          assert(via.include?("1.1 localhost.localdomain:#{port}"), up_log.call + log.call)
          assert_nil(res.body, up_log.call + log.call)
        }
        assert_equal(2, up_proxy_handler_called, up_log.call + log.call)
        assert_equal(4, up_request_handler_called, up_log.call + log.call)
        assert_equal(2, proxy_handler_called, up_log.call + log.call)
        assert_equal(2, request_handler_called, up_log.call + log.call)

        req = Net::HTTP::Post.new("/")
        req.body = "post-data"
        req.content_type = "application/x-www-form-urlencoded"
        http.request(req) { |res|
          via = res["via"].split(/,\s+/)
          assert(via.include?("1.1 localhost.localdomain:#{up_port}"), up_log.call + log.call)
          assert(via.include?("1.1 localhost.localdomain:#{port}"), up_log.call + log.call)
          assert_equal("POST / post-data", res.body, up_log.call + log.call)
        }
        assert_equal(3, up_proxy_handler_called, up_log.call + log.call)
        assert_equal(6, up_request_handler_called, up_log.call + log.call)
        assert_equal(3, proxy_handler_called, up_log.call + log.call)
        assert_equal(3, request_handler_called, up_log.call + log.call)
      }
    }
  end
end
