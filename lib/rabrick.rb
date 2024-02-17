# frozen_string_literal: false

##
# = WEB server toolkit.
#
# Rabrick is an HTTP server toolkit that can be configured as
# a proxy server, and a virtual-host server.  Rabrick features complete
# logging of both server operations and HTTP access.  Rabrick supports both
# basic and digest authentication in addition to algorithms not in RFC 2617.
#
# A Rabrick server can be composed of multiple Rabrick servers or servlets to
# provide differing behavior on a per-host or per-path basis.  Rabrick
# includes servlets for handling CGI scripts, ERB pages, Ruby blocks and
# directory listings.
#
# Rabrick also includes tools for daemonizing a process and starting a process
# at a higher privilege level and dropping permissions.
#
# == Security
#
# *Warning:* Rabrick is not recommended for production.  It only implements
# basic security checks.
#
# == Starting an HTTP server
#
# To run the server you will need to provide a suitable shutdown hook as
# starting the server blocks the current thread:
#
#   trap 'INT' do server.shutdown end
#
#   server.start
#
# == Rabrick as a daemonized Web Server
#
# Rabrick can be run as a daemonized server for small loads.
#
# === Daemonizing
#
# To start a Rabrick server as a daemon simple run Rabrick::Daemon.start
# before starting the server.
#
# === Dropping Permissions
#
# Rabrick can be started as one user to gain permission to bind to port 80 or
# 443 for serving HTTP traffic then can drop these permissions for
# regular operation.  To listen on all interfaces for HTTP traffic:
#
#   sockets = Rabrick::Utils.create_listeners nil, 80
#
# Then drop privileges:
#
#   Rabrick::Utils.su 'www'
#
# Then create a server that does not listen by default:
#
#   server = Rabrick::HTTPServer.new :DoNotListen => true, # ...
#
# Then overwrite the listening sockets with the port 80 sockets:
#
#   server.listeners.replace sockets
#
# === Logging
#
# Rabrick can separately log server operations and end-user access.  For
# server operations:
#
#   log_file = File.open '/var/log/rabrick.log', 'a+'
#   log = Rabrick::Log.new log_file
#
# For user access logging:
#
#   access_log = [
#     [log_file, Rabrick::AccessLog::COMBINED_LOG_FORMAT],
#   ]
#
#   server = Rabrick::HTTPServer.new :Logger => log, :AccessLog => access_log
#
# See Rabrick::AccessLog for further log formats.
#
# === Log Rotation
#
# To rotate logs in Rabrick on a HUP signal (like syslogd can send), open the
# log file in 'a+' mode (as above) and trap 'HUP' to reopen the log file:
#
#   trap 'HUP' do log_file.reopen '/path/to/rabrick.log', 'a+'
#
# == Copyright
#
# Author: IPR -- Internet Programming with Ruby -- writers
#
# Copyright (c) 2000 TAKAHASHI Masayoshi, GOTOU YUUZOU
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#--
# $IPR: rabrick.rb,v 1.12 2002/10/01 17:16:31 gotoyuzo Exp $

module Rabrick
end

require 'rabrick/compat'

require 'rabrick/version'
require 'rabrick/config'
require 'rabrick/log'
require 'rabrick/ractor_logger'
require 'rabrick/server'
require_relative 'rabrick/utils'
require 'rabrick/accesslog'

require 'rabrick/htmlutils'
require 'rabrick/httputils'
require 'rabrick/cookie'
require 'rabrick/null_io'
require 'rabrick/httpversion'
require 'rabrick/httpstatus'
require 'rabrick/httprequest'
require 'rabrick/httpresponse'
require 'rabrick/request_handler'
require 'rabrick/httpserver'
