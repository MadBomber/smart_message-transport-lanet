# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Load only the version first to allow basic tests
require "smart_message/transport/lanet/version"

require "minitest/autorun"
require "logger"
require "json"
require "socket"

# Mock SmartMessage::Transport::Base if not available
unless defined?(SmartMessage::Transport::Base)
  module SmartMessage
    VERSION = "0.1.0" unless defined?(VERSION)

    module Transport
      class Base
        attr_reader :options, :logger

        def initialize(**options)
          @options = default_options.merge(options)
          @logger = @options[:logger] || Logger.new($stdout)
        end

        def default_options
          {}
        end

        def subscribe(message_class, process_method, filter_options = {})
          # Mock implementation for testing
        end

        def unsubscribe(message_class, process_method)
          # Mock implementation for testing
        end

        def receive(message_class, payload)
          # Mock implementation for testing
        end
      end
    end
  end
end

# Mock Lanet module if not available
unless defined?(Lanet)
  module Lanet
    class Sender
      def initialize(config)
        @config = config
      end

      def discover_nodes(timeout:)
        []
      end

      def send_to_node(node_id, data, **options)
        true
      end

      def close
        true
      end
    end

    class Receiver
      def initialize(config, &block)
        @config = config
        @block = block
      end

      def close
        true
      end
    end
  end
end

# Now load the full Lanet transport
require "smart_message/transport/lanet"
