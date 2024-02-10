# frozen_string_literal: true

#--
# httpauth/authenticator.rb -- Authenticator mix-in module.
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: authenticator.rb,v 1.3 2003/02/20 07:15:47 gotoyuzo Exp $

module Rabrick
  module HTTPAuth
    ##
    # Module providing generic support for both Digest and Basic
    # authentication schemes.

    module Authenticator
      RequestField      = "Authorization" # :nodoc:
      ResponseField     = "WWW-Authenticate" # :nodoc:
      ResponseInfoField = "Authentication-Info" # :nodoc:
      AuthException     = HTTPStatus::Unauthorized # :nodoc:

      ##
      # Method of authentication, must be overridden by the including class

      AuthScheme        = nil

      ##
      # The realm this authenticator covers

      attr_reader :realm, :userdb, :logger

      ##
      # The user database for this authenticator

      ##
      # The logger for this authenticator

      private

      # :stopdoc:

      ##
      # Initializes the authenticator from +config+

      def check_init(config)
        %i[UserDB Realm].each { |sym|
          unless config[sym]
            raise ArgumentError, "Argument #{sym.inspect} missing."
          end
        }
        @realm     = config[:Realm]
        @userdb    = config[:UserDB]
        @reload_db = config[:AutoReloadUserDB]
        @request_field   = self.class::RequestField
        @response_field  = self.class::ResponseField
        @resp_info_field = self.class::ResponseInfoField
        @auth_exception  = self.class::AuthException
        @auth_scheme     = self.class::AuthScheme
      end

      ##
      # Ensures +req+ has credentials that can be authenticated.

      def check_scheme(req)
        unless credentials = req[@request_field]
          error("no credentials in the request.")
          return nil
        end
        unless match = /^#{@auth_scheme}\s+/i.match(credentials)
          error("invalid scheme in %s.", credentials)
          info("%s: %s", @request_field, credentials) if $DEBUG
          return nil
        end
        match.post_match
      end

      def log(meth, fmt, *args)
        msg = format("%s %s: ", @auth_scheme, @realm)
        msg << fmt % args
        Rabrick::RactorLogger.__send__(meth, msg)
      end

      def error(fmt, *args)
        if Rabrick::RactorLogger.error?
          log(:error, fmt, *args)
        end
      end

      def info(fmt, *args)
        if Rabrick::RactorLogger.info?
          log(:info, fmt, *args)
        end
      end

      # :startdoc:
    end

    ##
    # Module providing generic support for both Digest and Basic
    # authentication schemes for proxies.

    module ProxyAuthenticator
      RequestField  = "Proxy-Authorization" # :nodoc:
      ResponseField = "Proxy-Authenticate" # :nodoc:
      InfoField     = "Proxy-Authentication-Info" # :nodoc:
      AuthException = HTTPStatus::ProxyAuthenticationRequired # :nodoc:
    end
  end
end
