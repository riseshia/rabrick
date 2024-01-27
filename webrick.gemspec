# frozen_string_literal: true

begin
  require_relative 'lib/webrick/version'
rescue LoadError
  # for Ruby core repository
  require_relative 'version'
end

Gem::Specification.new do |s|
  s.name = "webrick"
  s.version = WEBrick::VERSION
  s.summary = "HTTP server toolkit"
  s.description = "WEBrick is an HTTP server toolkit that can be configured as an HTTPS server, a proxy server, and a virtual-host server."

  s.require_path = %w[lib]
  s.files = [
    "Gemfile",
    "LICENSE.txt",
    "README.md",
    "Rakefile",
    "lib/webrick.rb",
    "lib/webrick/accesslog.rb",
    "lib/webrick/cgi.rb",
    "lib/webrick/compat.rb",
    "lib/webrick/config.rb",
    "lib/webrick/cookie.rb",
    "lib/webrick/htmlutils.rb",
    "lib/webrick/httpauth.rb",
    "lib/webrick/httpauth/authenticator.rb",
    "lib/webrick/httpauth/basicauth.rb",
    "lib/webrick/httpauth/digestauth.rb",
    "lib/webrick/httpauth/htdigest.rb",
    "lib/webrick/httpauth/htgroup.rb",
    "lib/webrick/httpauth/htpasswd.rb",
    "lib/webrick/httpauth/userdb.rb",
    "lib/webrick/httpproxy.rb",
    "lib/webrick/httprequest.rb",
    "lib/webrick/httpresponse.rb",
    "lib/webrick/httpserver.rb",
    "lib/webrick/httpservlet.rb",
    "lib/webrick/httpservlet/abstract.rb",
    "lib/webrick/httpservlet/cgi_runner.rb",
    "lib/webrick/httpservlet/cgihandler.rb",
    "lib/webrick/httpservlet/erbhandler.rb",
    "lib/webrick/httpservlet/filehandler.rb",
    "lib/webrick/httpservlet/prochandler.rb",
    "lib/webrick/httpstatus.rb",
    "lib/webrick/httputils.rb",
    "lib/webrick/httpversion.rb",
    "lib/webrick/log.rb",
    "lib/webrick/server.rb",
    "lib/webrick/utils.rb",
    "lib/webrick/version.rb",
    "webrick.gemspec"
  ]
  s.required_ruby_version = ">= 3.2.0"

  s.authors = ["Shia"]
  s.email = ["rise.shia@gmail.com"]
  s.homepage = "https://github.com/riseshia/rabrick"
  s.licenses = ["Ruby", "BSD-2-Clause"]

  if s.respond_to?(:metadata=)
    s.metadata = {
      "bug_tracker_uri" => "https://github.com/riseshia/webrick/issues"
    }
  end
end
