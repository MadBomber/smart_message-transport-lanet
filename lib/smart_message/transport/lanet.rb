# frozen_string_literal: true

require_relative "lanet/version"
require 'smart_message/transport/base'
require 'lanet'

module SmartMessage
  module Transport
    class Lanet < Base
      class Error < StandardError; end
      
      DEFAULT_CONFIG = {
        port: ENV['LANET_PORT']&.to_i || 9999,
        broadcast_port: ENV['LANET_BROADCAST_PORT']&.to_i || 9998,
        encryption_key: ENV['LANET_ENCRYPTION_KEY'],
        signing_key: ENV['LANET_SIGNING_KEY'],
        discovery_timeout: ENV['LANET_DISCOVERY_TIMEOUT']&.to_f || 5.0,
        connection_timeout: ENV['LANET_CONNECTION_TIMEOUT']&.to_f || 10.0,
        heartbeat_interval: ENV['LANET_HEARTBEAT_INTERVAL']&.to_f || 30.0,
        max_message_size: ENV['LANET_MAX_MESSAGE_SIZE']&.to_i || 1048576, # 1MB
        enable_compression: ENV['LANET_ENABLE_COMPRESSION'] == 'true',
        node_id: ENV['LANET_NODE_ID'] || Socket.gethostname,
        network_interface: ENV['LANET_NETWORK_INTERFACE'] # Optional specific interface
      }.freeze

      attr_reader :sender, :receiver, :discovered_nodes, :node_registry

      def initialize(**options)
        super(**options)
        @discovered_nodes = {}
        @node_registry = {}
        @message_handlers = {}
        @discovery_thread = nil
        @heartbeat_thread = nil
        @shutdown = false
      end

      def configure
        setup_lanet_components
        start_discovery_service
        start_heartbeat_service
        logger.info { "[Lanet] Transport configured with node_id: #{@options[:node_id]}" }
      end

      def default_options
        DEFAULT_CONFIG
      end

      def do_publish(message_class, serialized_message)
        # For P2P, we need to determine target nodes
        # This could be based on message content, routing rules, or broadcast to all
        target_nodes = determine_target_nodes(message_class, serialized_message)
        
        if target_nodes.empty?
          logger.debug { "[Lanet] No target nodes found for #{message_class}, broadcasting to all discovered nodes" }
          target_nodes = @discovered_nodes.keys
        end

        publish_to_nodes(target_nodes, message_class, serialized_message)
      end

      def subscribe(message_class, process_method, filter_options = {})
        super(message_class, process_method, filter_options)
        
        # Register message handler if not already registered
        unless @message_handlers[message_class]
          register_message_handler(message_class)
        end
      end

      def unsubscribe(message_class, process_method)
        super(message_class, process_method)
        
        # Remove message handler if no more subscribers
        if @dispatcher.subscribers[message_class].empty?
          unregister_message_handler(message_class)
        end
      end

      def connected?
        !@shutdown && @sender && @receiver && @discovery_thread&.alive?
      end

      def connect
        configure
        logger.info { "[Lanet] Transport connected" }
      end

      def disconnect
        @shutdown = true
        
        # Stop threads
        @discovery_thread&.kill
        @heartbeat_thread&.kill
        
        # Cleanup Lanet components
        @sender&.close if @sender.respond_to?(:close)
        @receiver&.close if @receiver.respond_to?(:close)
        
        @discovered_nodes.clear
        @node_registry.clear
        
        logger.info { "[Lanet] Transport disconnected" }
      end

      # Public method to get discovered nodes for debugging/monitoring
      def network_topology
        {
          local_node: @options[:node_id],
          discovered_nodes: @discovered_nodes.dup,
          node_registry: @node_registry.dup,
          active_subscriptions: @message_handlers.keys
        }
      end

      # Manually discover nodes (useful for testing or forced discovery)
      def discover_nodes!
        perform_node_discovery
      end

      private

      def setup_lanet_components
        lanet_config = {
          port: @options[:port],
          broadcast_port: @options[:broadcast_port],
          node_id: @options[:node_id]
        }
        
        # Add encryption/signing keys if provided
        lanet_config[:encryption_key] = @options[:encryption_key] if @options[:encryption_key]
        lanet_config[:signing_key] = @options[:signing_key] if @options[:signing_key]
        lanet_config[:network_interface] = @options[:network_interface] if @options[:network_interface]

        @sender = ::Lanet::Sender.new(lanet_config)
        @receiver = ::Lanet::Receiver.new(lanet_config) do |message, sender_info|
          handle_incoming_message(message, sender_info)
        end
        
        logger.debug { "[Lanet] Lanet components initialized" }
      rescue => e
        logger.error { "[Lanet] Failed to setup Lanet components: #{e.message}" }
        raise Error, "Failed to initialize Lanet: #{e.message}"
      end

      def start_discovery_service
        @discovery_thread = Thread.new do
          Thread.current.name = "Lanet-Discovery"
          
          while !@shutdown
            begin
              perform_node_discovery
              sleep(@options[:discovery_timeout])
            rescue => e
              logger.error { "[Lanet] Discovery service error: #{e.message}" }
              sleep(5) # Back off on error
            end
          end
        end
        
        logger.debug { "[Lanet] Discovery service started" }
      end

      def start_heartbeat_service
        @heartbeat_thread = Thread.new do
          Thread.current.name = "Lanet-Heartbeat"
          
          while !@shutdown
            begin
              send_heartbeat
              cleanup_stale_nodes
              sleep(@options[:heartbeat_interval])
            rescue => e
              logger.error { "[Lanet] Heartbeat service error: #{e.message}" }
              sleep(10) # Back off on error
            end
          end
        end
        
        logger.debug { "[Lanet] Heartbeat service started" }
      end

      def perform_node_discovery
        # Use Lanet's discovery mechanism to find other nodes
        discovered = @sender.discover_nodes(timeout: @options[:discovery_timeout])
        
        discovered.each do |node_info|
          node_id = node_info[:node_id] || node_info['node_id']
          next unless node_id && node_id != @options[:node_id]
          
          @discovered_nodes[node_id] = {
            ip: node_info[:ip] || node_info['ip'],
            port: node_info[:port] || node_info['port'],
            last_seen: Time.now,
            capabilities: node_info[:capabilities] || node_info['capabilities'] || []
          }
        end
        
        logger.debug { "[Lanet] Discovered #{@discovered_nodes.size} nodes" } if @discovered_nodes.any?
      rescue => e
        logger.error { "[Lanet] Node discovery failed: #{e.message}" }
      end

      def send_heartbeat
        heartbeat_data = {
          node_id: @options[:node_id],
          timestamp: Time.now.to_f,
          message_types: @message_handlers.keys.map(&:to_s),
          smart_message_version: SmartMessage::VERSION
        }
        
        @discovered_nodes.keys.each do |node_id|
          begin
            @sender.send_to_node(node_id, heartbeat_data.to_json, type: 'heartbeat')
          rescue => e
            logger.debug { "[Lanet] Heartbeat failed to #{node_id}: #{e.message}" }
          end
        end
      end

      def cleanup_stale_nodes
        stale_threshold = Time.now - (@options[:heartbeat_interval] * 3)
        
        @discovered_nodes.reject! do |node_id, node_info|
          if node_info[:last_seen] < stale_threshold
            logger.debug { "[Lanet] Removing stale node: #{node_id}" }
            @node_registry.delete(node_id)
            true
          else
            false
          end
        end
      end

      def determine_target_nodes(message_class, serialized_message)
        # Parse message to extract routing information
        # This is a simple implementation - could be enhanced with more sophisticated routing
        
        begin
          # Try to parse the message to extract routing hints
          message_data = JSON.parse(serialized_message)
          header = message_data['_sm_header'] || {}
          
          # Check for specific target in the header
          if header['to'] && header['to'] != 'broadcast'
            target_node = header['to']
            return @discovered_nodes.key?(target_node) ? [target_node] : []
          end
          
          # Check for node capabilities matching
          required_capabilities = header['capabilities'] || []
          if required_capabilities.any?
            return @discovered_nodes.select do |node_id, node_info|
              capabilities = node_info[:capabilities] || []
              required_capabilities.all? { |cap| capabilities.include?(cap) }
            end.keys
          end
          
        rescue JSON::ParserError
          # If we can't parse the message, fall back to broadcast
        end
        
        # Default: return all discovered nodes
        @discovered_nodes.keys
      end

      def publish_to_nodes(target_nodes, message_class, serialized_message)
        published_count = 0
        
        target_nodes.each do |node_id|
          begin
            @sender.send_to_node(
              node_id, 
              serialized_message,
              type: 'smart_message',
              message_class: message_class.to_s,
              encrypt: true
            )
            published_count += 1
          rescue => e
            logger.warn { "[Lanet] Failed to send to #{node_id}: #{e.message}" }
          end
        end
        
        logger.debug { "[Lanet] Published #{message_class} to #{published_count}/#{target_nodes.size} nodes" }
      end

      def register_message_handler(message_class)
        @message_handlers[message_class] = true
        logger.debug { "[Lanet] Registered handler for #{message_class}" }
      end

      def unregister_message_handler(message_class)
        @message_handlers.delete(message_class)
        logger.debug { "[Lanet] Unregistered handler for #{message_class}" }
      end

      def handle_incoming_message(message, sender_info)
        begin
          # Handle different message types
          case message[:type] || message['type']
          when 'heartbeat'
            handle_heartbeat(message, sender_info)
          when 'smart_message'
            handle_smart_message(message, sender_info)
          else
            logger.debug { "[Lanet] Unknown message type: #{message[:type] || message['type']}" }
          end
        rescue => e
          logger.error { "[Lanet] Error handling incoming message: #{e.message}" }
        end
      end

      def handle_heartbeat(message, sender_info)
        node_id = message[:node_id] || message['node_id']
        return unless node_id
        
        # Update node registry with heartbeat info
        @node_registry[node_id] = {
          ip: sender_info[:ip] || sender_info['ip'],
          port: sender_info[:port] || sender_info['port'],
          last_heartbeat: Time.now,
          message_types: message[:message_types] || message['message_types'] || [],
          smart_message_version: message[:smart_message_version] || message['smart_message_version']
        }
        
        # Update discovered nodes timestamp
        if @discovered_nodes[node_id]
          @discovered_nodes[node_id][:last_seen] = Time.now
        end
      end

      def handle_smart_message(message, sender_info)
        message_class = message[:message_class] || message['message_class']
        payload = message[:payload] || message['payload'] || message.to_s
        
        return unless message_class && payload
        
        # Only process if we have subscribers for this message class
        if @message_handlers[message_class.to_s]
          receive(message_class, payload)
        else
          logger.debug { "[Lanet] No handlers for message class: #{message_class}" }
        end
      end
    end
  end
end
