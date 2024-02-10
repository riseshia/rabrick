# frozen_string_literal: false

require "test/unit"
require "net/http"
require "tempfile"
require "rabrick"
require "rabrick/httpauth/basicauth"
require "stringio"
require_relative "utils"

class TestWEBrickHTTPAuth < Test::Unit::TestCase
  def teardown
    Rabrick::Utils::TimeoutHandler.terminate
    super
  end

  def test_basic_auth
    omit

    log_tester = lambda { |log, _access_log|
      assert_equal(1, log.length)
      assert_match(/ERROR Rabrick::HTTPStatus::Unauthorized/, log[0])
    }
    TestWEBrick.start_httpserver({}, log_tester) { |server, addr, port, log|
      realm = "Rabrick's realm"
      path = "/basic_auth"

      server.mount_proc(path) { |req, res|
        Rabrick::HTTPAuth.basic_auth(req, res, realm) { |user, pass|
          user == "rabrick" && pass == "supersecretpassword"
        }
        res.body = "hoge"
      }
      http = Net::HTTP.new(addr, port)
      g = Net::HTTP::Get.new(path)
      g.basic_auth("rabrick", "supersecretpassword")
      http.request(g) { |res| assert_equal("hoge", res.body, log.call) }
      g.basic_auth("rabrick", "not super")
      http.request(g) { |res| assert_not_equal("hoge", res.body, log.call) }
    }
  end

  def test_basic_auth_sha
    Tempfile.create("test_rabrick_auth") { |tmpfile|
      tmpfile.puts("rabrick:{SHA}GJYFRpBbdchp595jlh3Bhfmgp8k=")
      tmpfile.flush
      assert_raise(NotImplementedError) {
        Rabrick::HTTPAuth::Htpasswd.new(tmpfile.path)
      }
    }
  end

  def test_basic_auth_md5
    Tempfile.create("test_rabrick_auth") { |tmpfile|
      tmpfile.puts("rabrick:$apr1$IOVMD/..$rmnOSPXr0.wwrLPZHBQZy0")
      tmpfile.flush
      assert_raise(NotImplementedError) {
        Rabrick::HTTPAuth::Htpasswd.new(tmpfile.path)
      }
    }
  end

  [nil, :crypt, :bcrypt].each do |hash_algo|
    # OpenBSD does not support insecure DES-crypt
    next if /openbsd/ =~ RUBY_PLATFORM && hash_algo != :bcrypt

    begin
      case hash_algo
      when :crypt
        # require 'string/crypt'
      when :bcrypt
        require 'bcrypt'
      end
    rescue LoadError
      next
    end

    define_method(:"test_basic_auth_htpasswd_#{hash_algo}") do
      omit

      log_tester = lambda { |log, _access_log|
        log.reject! { |line| /\A\s*\z/ =~ line }
        pats = [
          /ERROR Basic Rabrick's realm: rabrick: password unmatch\./,
          /ERROR Rabrick::HTTPStatus::Unauthorized/
        ]
        pats.each { |pat|
          assert(!log.grep(pat).empty?, "rabrick log doesn't have expected error: #{pat.inspect}")
          log.reject! { |line| pat =~ line }
        }
        assert_equal([], log)
      }
      TestWEBrick.start_httpserver({}, log_tester) { |server, addr, port, log|
        realm = "Rabrick's realm"
        path = "/basic_auth2"

        Tempfile.create("test_rabrick_auth") { |tmpfile|
          tmpfile.close
          tmp_pass = Rabrick::HTTPAuth::Htpasswd.new(tmpfile.path, password_hash: hash_algo)
          tmp_pass.set_passwd(realm, "rabrick", "supersecretpassword")
          tmp_pass.set_passwd(realm, "foo", "supersecretpassword")
          tmp_pass.flush

          htpasswd = Rabrick::HTTPAuth::Htpasswd.new(tmpfile.path, password_hash: hash_algo)
          users = []
          htpasswd.each { |user, _pass| users << user }
          assert_equal(2, users.size, log.call)
          assert(users.member?("rabrick"), log.call)
          assert(users.member?("foo"), log.call)

          server.mount_proc(path) { |req, res|
            auth = Rabrick::HTTPAuth::BasicAuth.new(
              :Realm => realm, :UserDB => htpasswd,
              :Logger => server.logger
            )
            auth.authenticate(req, res)
            res.body = "hoge"
          }
          http = Net::HTTP.new(addr, port)
          g = Net::HTTP::Get.new(path)
          g.basic_auth("rabrick", "supersecretpassword")
          http.request(g) { |res| assert_equal("hoge", res.body, log.call) }
          g.basic_auth("rabrick", "not super")
          http.request(g) { |res| assert_not_equal("hoge", res.body, log.call) }
        }
      }
    end

    define_method(:"test_basic_auth_bad_username_htpasswd_#{hash_algo}") do
      omit

      log_tester = lambda { |log, _access_log|
        assert_equal(2, log.length)
        assert_match(/ERROR Basic Rabrick's realm: foo\\ebar: the user is not allowed\./, log[0])
        assert_match(/ERROR Rabrick::HTTPStatus::Unauthorized/, log[1])
      }
      TestWEBrick.start_httpserver({}, log_tester) { |server, addr, port, log|
        realm = "Rabrick's realm"
        path = "/basic_auth"

        Tempfile.create("test_rabrick_auth") { |tmpfile|
          tmpfile.close
          tmp_pass = Rabrick::HTTPAuth::Htpasswd.new(tmpfile.path, password_hash: hash_algo)
          tmp_pass.set_passwd(realm, "rabrick", "supersecretpassword")
          tmp_pass.set_passwd(realm, "foo", "supersecretpassword")
          tmp_pass.flush

          htpasswd = Rabrick::HTTPAuth::Htpasswd.new(tmpfile.path, password_hash: hash_algo)
          users = []
          htpasswd.each { |user, _pass| users << user }
          server.mount_proc(path) { |req, res|
            auth = Rabrick::HTTPAuth::BasicAuth.new(
              :Realm => realm, :UserDB => htpasswd,
              :Logger => server.logger
            )
            auth.authenticate(req, res)
            res.body = "hoge"
          }
          http = Net::HTTP.new(addr, port)
          g = Net::HTTP::Get.new(path)
          g.basic_auth("foo\ebar", "passwd")
          http.request(g) { |res| assert_not_equal("hoge", res.body, log.call) }
        }
      }
    end
  end

  DIGESTRES_ = /
    ([a-zA-Z-]+)
      [ \t]*(?:\r\n[ \t]*)*
      =
      [ \t]*(?:\r\n[ \t]*)*
      (?:
       "((?:[^"]+|\\[\x00-\x7F])*)" |
       ([!\#$%&'*+\-.0-9A-Z^_`a-z|~]+)
      )/x

  def test_digest_auth
    omit

    log_tester = lambda { |log, _access_log|
      log.reject! { |line| /\A\s*\z/ =~ line }
      pats = [
        /ERROR Digest Rabrick's realm: no credentials in the request\./,
        /ERROR Rabrick::HTTPStatus::Unauthorized/,
        /ERROR Digest Rabrick's realm: rabrick: digest unmatch\./
      ]
      pats.each { |pat|
        assert(!log.grep(pat).empty?, "rabrick log doesn't have expected error: #{pat.inspect}")
        log.reject! { |line| pat =~ line }
      }
      assert_equal([], log)
    }
    TestWEBrick.start_httpserver({}, log_tester) { |server, addr, port, log|
      realm = "Rabrick's realm"
      path = "/digest_auth"

      Tempfile.create("test_rabrick_auth") { |tmpfile|
        tmpfile.close
        tmp_pass = Rabrick::HTTPAuth::Htdigest.new(tmpfile.path)
        tmp_pass.set_passwd(realm, "rabrick", "supersecretpassword")
        tmp_pass.set_passwd(realm, "foo", "supersecretpassword")
        tmp_pass.flush

        htdigest = Rabrick::HTTPAuth::Htdigest.new(tmpfile.path)
        users = []
        htdigest.each { |user, _pass| users << user }
        assert_equal(2, users.size, log.call)
        assert(users.member?("rabrick"), log.call)
        assert(users.member?("foo"), log.call)

        auth = Rabrick::HTTPAuth::DigestAuth.new(
          :Realm => realm, :UserDB => htdigest,
          :Algorithm => 'MD5',
          :Logger => server.logger
        )
        server.mount_proc(path) { |req, res|
          auth.authenticate(req, res)
          res.body = "hoge"
        }

        Net::HTTP.start(addr, port) do |http|
          g = Net::HTTP::Get.new(path)
          params = {}
          http.request(g) do |res|
            assert_equal('401', res.code, log.call)
            res["www-authenticate"].scan(DIGESTRES_) do |key, quoted, token|
              params[key.downcase] = token || quoted.delete('\\')
            end
            params['uri'] = "http://#{addr}:#{port}#{path}"
          end

          g['Authorization'] = credentials_for_request('rabrick', "supersecretpassword", params)
          http.request(g) { |res| assert_equal("hoge", res.body, log.call) }

          params['algorithm'].downcase! # 4936
          g['Authorization'] = credentials_for_request('rabrick', "supersecretpassword", params)
          http.request(g) { |res| assert_equal("hoge", res.body, log.call) }

          g['Authorization'] = credentials_for_request('rabrick', "not super", params)
          http.request(g) { |res| assert_not_equal("hoge", res.body, log.call) }
        end
      }
    }
  end

  def test_digest_auth_int
    omit

    log_tester = lambda { |log, _access_log|
      log.reject! { |line| /\A\s*\z/ =~ line }
      pats = [
        /ERROR Digest wb auth-int realm: no credentials in the request\./,
        /ERROR Rabrick::HTTPStatus::Unauthorized/,
        /ERROR Digest wb auth-int realm: foo: digest unmatch\./
      ]
      pats.each { |pat|
        assert(!log.grep(pat).empty?, "rabrick log doesn't have expected error: #{pat.inspect}")
        log.reject! { |line| pat =~ line }
      }
      assert_equal([], log)
    }
    TestWEBrick.start_httpserver({}, log_tester) { |server, addr, port, log|
      realm = "wb auth-int realm"
      path = "/digest_auth_int"

      Tempfile.create("test_rabrick_auth_int") { |tmpfile|
        tmpfile.close
        tmp_pass = Rabrick::HTTPAuth::Htdigest.new(tmpfile.path)
        tmp_pass.set_passwd(realm, "foo", "Hunter2")
        tmp_pass.flush

        htdigest = Rabrick::HTTPAuth::Htdigest.new(tmpfile.path)
        users = []
        htdigest.each { |user, _pass| users << user }
        assert_equal %w[foo], users

        auth = Rabrick::HTTPAuth::DigestAuth.new(
          :Realm => realm, :UserDB => htdigest,
          :Algorithm => 'MD5',
          :Logger => server.logger,
          :Qop => %w[auth-int]
        )
        server.mount_proc(path) { |req, res|
          auth.authenticate(req, res)
          res.body = "bbb"
        }
        Net::HTTP.start(addr, port) do |http|
          post = Net::HTTP::Post.new(path)
          params = {}
          data = 'hello=world'
          body = StringIO.new(data)
          post.content_length = data.bytesize
          post['Content-Type'] = 'application/x-www-form-urlencoded'
          post.body_stream = body

          http.request(post) do |res|
            assert_equal('401', res.code, log.call)
            res["www-authenticate"].scan(DIGESTRES_) do |key, quoted, token|
              params[key.downcase] = token || quoted.delete('\\')
            end
            params['uri'] = "http://#{addr}:#{port}#{path}"
          end

          body.rewind
          cred = credentials_for_request('foo', 'Hunter3', params, body)
          post['Authorization'] = cred
          post.body_stream = body
          http.request(post) { |res|
            assert_equal('401', res.code, log.call)
            assert_not_equal("bbb", res.body, log.call)
          }

          body.rewind
          cred = credentials_for_request('foo', 'Hunter2', params, body)
          post['Authorization'] = cred
          post.body_stream = body
          http.request(post) { |res| assert_equal("bbb", res.body, log.call) }
        end
      }
    }
  end

  def test_digest_auth_invalid
    digest_auth = Rabrick::HTTPAuth::DigestAuth.new(Realm: 'realm', UserDB: '')

    def digest_auth.error(fmt, *)
    end

    def digest_auth.try_bad_request(len)
      request = { "Authorization" => %(Digest a="#{'\b' * len}) }
      authenticate request, nil
    end

    bad_request = Rabrick::HTTPStatus::BadRequest
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raise(bad_request) { digest_auth.try_bad_request(10) }
    limit = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)
    [20, 50, 100, 200].each do |len|
      assert_raise(bad_request) do
        Timeout.timeout(len * limit) { digest_auth.try_bad_request(len) }
      end
    end
  end

  private

  def credentials_for_request(user, password, params, body = nil)
    cnonce = "hoge"
    nonce_count = 1
    ha1 = "#{user}:#{params['realm']}:#{password}"
    if body
      dig = Digest::MD5.new
      while buf = body.read(16_384)
        dig.update(buf)
      end
      body.rewind
      ha2 = "POST:#{params['uri']}:#{dig.hexdigest}"
    else
      ha2 = "GET:#{params['uri']}"
    end

    request_digest =
      "#{Digest::MD5.hexdigest(ha1)}:" \
      "#{params['nonce']}:#{'%08x' % nonce_count}:#{cnonce}:#{params['qop']}:" \
      "#{Digest::MD5.hexdigest(ha2)}"
    "Digest username=\"#{user}\"" \
      ", realm=\"#{params['realm']}\"" \
      ", nonce=\"#{params['nonce']}\"" \
      ", uri=\"#{params['uri']}\"" \
      ", qop=#{params['qop']}" \
      ", nc=#{'%08x' % nonce_count}" \
      ", cnonce=\"#{cnonce}\"" \
      ", response=\"#{Digest::MD5.hexdigest(request_digest)}\"" \
      ", opaque=\"#{params['opaque']}\"" \
      ", algorithm=#{params['algorithm']}"
  end
end
