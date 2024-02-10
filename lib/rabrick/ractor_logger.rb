# frozen_string_literal: true
# shareable_constant_value: experimental_everything

module Rabrick
  module RactorLogger
    module_function

    def fatal(msg)
      StderrLoggerRactor.send([:fatal, msg])
    end

    def error(msg)
      StderrLoggerRactor.send([:error, msg])
    end

    def warn(msg)
      StderrLoggerRactor.send([:warn, msg])
    end

    def info(msg)
      StderrLoggerRactor.send([:info, msg])
    end

    def debug(msg)
      StderrLoggerRactor.send([:debug, msg])
    end

    def fatal?
      StderrLoggerRactor.send([:fatal?])
    end

    def error?
      StderrLoggerRactor.send([:error?])
    end

    def warn?
      StderrLoggerRactor.send([:warn?])
    end

    def info?
      StderrLoggerRactor.send([:info?])
    end

    def debug?
      StderrLoggerRactor.send([:debug?])
    end
  end

  module RactorAccessLogger
    module_function

    def puts(str)
      AccessLoggerRactor.send(str)
    end
  end

  StderrLoggerRactor = Ractor.new do
    logger = Rabrick::Log.new($stderr)

    loop do
      m, v = Ractor.receive
      if m.end_with?('?')
        logger.send(m)
      else
        logger.send(m, v)
      end
    end
  end

  AccessLoggerRactor = Ractor.new do
    loop do
      msg = Ractor.receive
      $stdout.puts msg
    end
  end
end
