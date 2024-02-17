# frozen_string_literal: true

module Rabrick
  class NullIO
    def gets = nil
    def close = nil

    def read(length = 0, outbuf = nil)
      if length.to_i < 0
        raise ArgumentError, "negative #{length} given."
      end

      if outbuf && String.try_convert(outbuf).nil?
        raise(TypeError, "can't convert #{outbuf.class} to String")
      end

      outbuf&.clear

      length.positive? ? nil : ""
    end

    def each
      Enumerator.new do |y|
        y << nil
      end
    end
  end
end
