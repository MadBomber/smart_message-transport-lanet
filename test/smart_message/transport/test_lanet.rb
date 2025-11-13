# frozen_string_literal: true

require "test_helper"

class SmartMessage::Transport::TestLanet < Minitest::Test
  def setup
    @transport = create_transport
  end

  def teardown
    @transport.disconnect if @transport&.connected?
  end

  def test_that_it_has_a_version_number
    refute_nil ::SmartMessage::Transport::Lanet::VERSION
  end

  def test_version_format
    assert_match(/\d+\.\d+\.\d+/, ::SmartMessage::Transport::Lanet::VERSION)
  end

  def test_initialization_with_default_options
    transport = create_transport

    assert_instance_of SmartMessage::Transport::Lanet, transport
    assert_equal({}, transport.discovered_nodes)
    assert_equal({}, transport.node_registry)
  end

  def test_initialization_with_custom_options
    transport = create_transport(
      port: 8888,
      node_id: "test-node-123"
    )

    assert_instance_of SmartMessage::Transport::Lanet, transport
  end

  def test_default_options_structure
    transport = create_transport
    defaults = transport.send(:default_options)

    # Verify the defaults hash has the expected keys
    assert_includes defaults, :port
    assert_includes defaults, :broadcast_port
    assert_includes defaults, :node_id
    assert_includes defaults, :discovery_timeout
    assert_includes defaults, :heartbeat_interval
    assert_includes defaults, :max_message_size
  end

  def test_default_config_constants
    config = SmartMessage::Transport::Lanet::DEFAULT_CONFIG

    assert_kind_of Integer, config[:port]
    assert_kind_of Integer, config[:broadcast_port]
    assert_kind_of Float, config[:discovery_timeout]
    assert_kind_of Float, config[:connection_timeout]
    assert_kind_of Float, config[:heartbeat_interval]
    assert_kind_of Integer, config[:max_message_size]
    assert_includes [true, false], config[:enable_compression]
    refute_nil config[:node_id]
  end

  def test_configure_initializes_lanet_components
    transport = create_transport
    mock_sender = Minitest::Mock.new
    mock_receiver = Minitest::Mock.new

    # Mock the Lanet components
    ::Lanet::Sender.stub :new, mock_sender do
      ::Lanet::Receiver.stub :new, mock_receiver do
        transport.configure

        assert transport.sender
        assert transport.receiver
      end
    end
  end

  def test_connected_status_when_not_connected
    transport = create_transport
    refute transport.connected?
  end

  def test_network_topology_returns_proper_structure
    transport = create_transport
    topology = transport.network_topology

    assert_kind_of Hash, topology
    assert_includes topology, :local_node
    assert_includes topology, :discovered_nodes
    assert_includes topology, :node_registry
    assert_includes topology, :active_subscriptions
  end

  def test_network_topology_includes_node_id
    transport = create_transport(node_id: "test-node-456")
    topology = transport.network_topology

    assert_equal "test-node-456", topology[:local_node]
  end

  def test_error_class_exists
    assert defined?(SmartMessage::Transport::Lanet::Error)
    assert SmartMessage::Transport::Lanet::Error < StandardError
  end

  def test_disconnect_clears_internal_state
    transport = create_transport

    # Add some mock data
    transport.instance_variable_set(:@discovered_nodes, { "node1" => {} })
    transport.instance_variable_set(:@node_registry, { "node1" => {} })

    transport.disconnect

    assert_empty transport.discovered_nodes
    assert_empty transport.node_registry
  end

  def test_determine_target_nodes_with_no_header
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 },
      "node2" => { ip: "192.168.1.11", port: 9999 }
    })

    message = { some: "data" }.to_json
    targets = transport.send(:determine_target_nodes, "TestMessage", message)

    assert_equal ["node1", "node2"], targets.sort
  end

  def test_determine_target_nodes_with_specific_target
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 },
      "node2" => { ip: "192.168.1.11", port: 9999 }
    })

    message = { _sm_header: { to: "node1" } }.to_json
    targets = transport.send(:determine_target_nodes, "TestMessage", message)

    assert_equal ["node1"], targets
  end

  def test_determine_target_nodes_with_broadcast_header
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 },
      "node2" => { ip: "192.168.1.11", port: 9999 }
    })

    message = { _sm_header: { to: "broadcast" } }.to_json
    targets = transport.send(:determine_target_nodes, "TestMessage", message)

    assert_equal ["node1", "node2"], targets.sort
  end

  def test_determine_target_nodes_with_capabilities
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, capabilities: ["storage"] },
      "node2" => { ip: "192.168.1.11", port: 9999, capabilities: ["compute", "storage"] },
      "node3" => { ip: "192.168.1.12", port: 9999, capabilities: ["compute"] }
    })

    message = { _sm_header: { capabilities: ["storage"] } }.to_json
    targets = transport.send(:determine_target_nodes, "TestMessage", message)

    assert_equal ["node1", "node2"], targets.sort
  end

  def test_cleanup_stale_nodes_removes_old_nodes
    transport = create_transport(heartbeat_interval: 10.0)

    old_time = Time.now - 100
    recent_time = Time.now - 5

    transport.instance_variable_set(:@discovered_nodes, {
      "stale_node" => { ip: "192.168.1.10", port: 9999, last_seen: old_time },
      "active_node" => { ip: "192.168.1.11", port: 9999, last_seen: recent_time }
    })

    transport.instance_variable_set(:@node_registry, {
      "stale_node" => { last_heartbeat: old_time },
      "active_node" => { last_heartbeat: recent_time }
    })

    transport.send(:cleanup_stale_nodes)

    refute_includes transport.discovered_nodes.keys, "stale_node"
    assert_includes transport.discovered_nodes.keys, "active_node"
    refute_includes transport.node_registry.keys, "stale_node"
  end

  def test_handle_heartbeat_updates_node_registry
    transport = create_transport

    message = {
      node_id: "remote_node",
      timestamp: Time.now.to_f,
      message_types: ["TestMessage"],
      smart_message_version: "0.1.0"
    }

    sender_info = {
      ip: "192.168.1.100",
      port: 9999
    }

    transport.send(:handle_heartbeat, message, sender_info)

    assert_includes transport.node_registry.keys, "remote_node"
    assert_equal "192.168.1.100", transport.node_registry["remote_node"][:ip]
    assert_equal 9999, transport.node_registry["remote_node"][:port]
    assert_equal ["TestMessage"], transport.node_registry["remote_node"][:message_types]
  end

  def test_handle_heartbeat_with_string_keys
    transport = create_transport

    message = {
      "node_id" => "remote_node",
      "timestamp" => Time.now.to_f,
      "message_types" => ["TestMessage"],
      "smart_message_version" => "0.1.0"
    }

    sender_info = {
      "ip" => "192.168.1.100",
      "port" => 9999
    }

    transport.send(:handle_heartbeat, message, sender_info)

    assert_includes transport.node_registry.keys, "remote_node"
  end

  def test_handle_heartbeat_updates_discovered_nodes_timestamp
    transport = create_transport

    old_time = Time.now - 60
    transport.instance_variable_set(:@discovered_nodes, {
      "remote_node" => { ip: "192.168.1.100", port: 9999, last_seen: old_time }
    })

    message = {
      node_id: "remote_node",
      timestamp: Time.now.to_f
    }

    sender_info = { ip: "192.168.1.100", port: 9999 }

    transport.send(:handle_heartbeat, message, sender_info)

    assert transport.discovered_nodes["remote_node"][:last_seen] > old_time
  end

  def test_register_and_unregister_message_handler
    transport = create_transport

    transport.send(:register_message_handler, "TestMessage")
    handlers = transport.instance_variable_get(:@message_handlers)

    assert_includes handlers.keys, "TestMessage"

    transport.send(:unregister_message_handler, "TestMessage")
    handlers = transport.instance_variable_get(:@message_handlers)

    refute_includes handlers.keys, "TestMessage"
  end

  def test_handle_incoming_message_routes_heartbeat
    transport = create_transport

    message = { type: "heartbeat", node_id: "test_node" }
    sender_info = { ip: "192.168.1.100", port: 9999 }

    # Should not raise an error
    transport.send(:handle_incoming_message, message, sender_info)

    assert_includes transport.node_registry.keys, "test_node"
  end

  def test_handle_incoming_message_with_unknown_type
    transport = create_transport

    message = { type: "unknown_type" }
    sender_info = { ip: "192.168.1.100", port: 9999 }

    # Should not raise an error, just log
    transport.send(:handle_incoming_message, message, sender_info)
  end

  private

  def create_transport(**options)
    # Create a basic transport without connecting to avoid needing actual Lanet gems
    SmartMessage::Transport::Lanet.allocate.tap do |transport|
      default_options = {
        port: 9999,
        broadcast_port: 9998,
        node_id: "test-node",
        discovery_timeout: 5.0,
        heartbeat_interval: 30.0,
        logger: Logger.new(IO::NULL)
      }

      merged_options = default_options.merge(options)
      transport.instance_variable_set(:@options, merged_options)
      transport.instance_variable_set(:@logger, merged_options[:logger])
      transport.instance_variable_set(:@discovered_nodes, {})
      transport.instance_variable_set(:@node_registry, {})
      transport.instance_variable_set(:@message_handlers, {})
      transport.instance_variable_set(:@shutdown, false)
    end
  end
end
