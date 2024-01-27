module WEBrick
  module RactorLogger
    module_function

    def fatal(msg)
      RactorLoggerInternal.send([:fatal, msg])
    end

    def error(msg)
      RactorLoggerInternal.send([:error, msg])
    end

    def warn(msg)
      RactorLoggerInternal.send([:warn, msg])
    end

    def info(msg)
      RactorLoggerInternal.send([:info, msg])
    end

    def debug(msg)
      RactorLoggerInternal.send([:debug, msg])
    end

    def fatal?
      RactorLoggerInternal.send([:fatal?])
    end

    def error?
      RactorLoggerInternal.send([:error?])
    end

    def warn?
      RactorLoggerInternal.send([:warn?])
    end

    def info?
      RactorLoggerInternal.send([:info?])
    end

    def debug?
      RactorLoggerInternal.send([:debug?])
    end
  end

  RactorLoggerInternal = Ractor.new do
    logger = WEBrick::Log.new($stderr)

    loop do
      m, v = Ractor.receive
      if m.end_with?('?')
        logger.send(m)
      else
        logger.send(m, v)
      end
    end
  end
end
