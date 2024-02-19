# frozen_string_literal: true

begin
  require_relative 'lib/rabrick/version'
rescue LoadError
  # for Ruby core repository
  require_relative 'version'
end

Gem::Specification.new do |s|
  s.name = "rabrick"
  s.version = Rabrick::VERSION
  s.summary = "HTTP server toolkit"
  s.description = "Rabrick is an HTTP server toolkit that can be configured as an HTTPS server, a proxy server, and a virtual-host server."

  s.require_path = %w[lib]
  s.files = [
    "Gemfile",
    "LICENSE.txt",
    "README.md",
    "Rakefile",
    "lib/rabrick.rb",
    "lib/rabrick/accesslog.rb",
    "lib/rabrick/compat.rb",
    "lib/rabrick/config.rb",
    "lib/rabrick/cookie.rb",
    "lib/rabrick/null_io.rb",
    "lib/rabrick/htmlutils.rb",
    "lib/rabrick/httprequest.rb",
    "lib/rabrick/httpresponse.rb",
    "lib/rabrick/httpserver.rb",
    "lib/rabrick/httpstatus.rb",
    "lib/rabrick/httputils.rb",
    "lib/rabrick/httpversion.rb",
    "lib/rabrick/log.rb",
    "lib/rabrick/request_handler.rb",
    "lib/rabrick/server.rb",
    "lib/rabrick/utils.rb",
    "lib/rabrick/version.rb",
    "lib/rabrick/rackup_register.rb",
    "lib/rack/handler/rabrick.rb",
    "rabrick.gemspec",
  ]
  s.required_ruby_version = ">= 3.2.0"

  s.authors = ["Shia"]
  s.email = ["rise.shia@gmail.com"]
  s.homepage = "https://github.com/riseshia/rabrick"
  s.licenses = ["Ruby", "BSD-2-Clause"]

  s.add_runtime_dependency "nbproc"

  if s.respond_to?(:metadata=)
    s.metadata = {
      "bug_tracker_uri" => "https://github.com/riseshia/rabrick/issues"
    }
  end
end
