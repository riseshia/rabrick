# frozen_string_literal: true

#
# config.rb -- Default configurations.
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: config.rb,v 1.52 2003/07/22 19:20:42 gotoyuzo Exp $

require_relative 'version'
require_relative 'httpversion'
require_relative 'httputils'
require_relative 'utils'
require_relative 'log'

module Rabrick
  module Config
    LIBDIR = File.dirname(__FILE__) # :nodoc:

    # for GenericServer
    General = Hash.new { |hash, key|
      case key
      when :ServerName
        hash[key] = Utils.getservername
      end
    }.update(
      :BindAddress => nil, # "0.0.0.0" or "::" or nil
      :Port => nil, # users MUST specify this!!
      :MaxClients => 100,   # maximum number of the concurrent connections
      :ServerType => nil,   # default: Rabrick::SimpleServer
      :ServerSoftware => "Rabrick/#{Rabrick::VERSION} " +
                         "(Ruby/#{RUBY_VERSION}/#{RUBY_RELEASE_DATE})",
      :TempDir => ENV['TMPDIR'] || ENV['TMP'] || ENV['TEMP'] || '/tmp',
      :DoNotListen => false,
      :DoNotReverseLookup => true,
      :ShutdownSocketWithoutClose => false
    )

    # for HTTPServer, HTTPRequest, HTTPResponse ...
    HTTP = General.dup.update(
      :Port => 80,
      :RequestTimeout => 30,
      :HTTPVersion => HTTPVersion.new("1.1"),
      :AccessLog => nil,
      :MimeTypes => HTTPUtils::DefaultMimeTypes,
      :DirectoryIndex => ["index.html", "index.htm", "index.rhtml"],
      :ServerAlias => nil,
      :InputBufferSize => 65_536, # input buffer size in reading request body
      :OutputBufferSize => 65_536, # output buffer size in sending File or IO

      # for HTTPProxyServer
      :ProxyAuthProc => nil,
      :ProxyContentHandler => nil,
      :ProxyVia => true,
      :ProxyTimeout => true,
      :ProxyURI => nil,

      :CGIInterpreter => nil,
      :CGIPathEnv => nil,

      # workaround: if Request-URIs contain 8bit chars,
      # they should be escaped before calling of URI::parse().
      :Escape8bitURI => false
    )

    module_function

    def make_shareable(config)
      # To eliminate init Proc, initialize new hash and copy values.
      new_config = {}.tap do |h|
        config.each do |k, v|
          h[k] = v
        end
      end

      Ractor.make_shareable(new_config)
    end
  end
end
