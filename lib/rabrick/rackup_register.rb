# frozen_string_literal: true

require_relative "../rack/handler/rabrick"

if Object.const_defined?(:Rackup)
  module Rackup
    module Handler
      module Rabrick
        class << self
          include ::Rabrick::Handler
        end
      end

      register :rabrick, Rabrick
    end
  end
elsif Object.const_defined?(:Rack) && Rack.release < "3"
  module Rack
    module Handler
      module Rabrick
        class << self
          include ::Rabrick::Handler
        end
      end
    end
  end

  ::Rack::Handler.register :rabrick, ::Rack::Handler::Rabrick
else
  raise "Rack 3 must be used with the rackup."
end
