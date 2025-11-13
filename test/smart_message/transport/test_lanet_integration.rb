# frozen_string_literal: true

require "test_helper"

class SmartMessage::Transport::TestLanetIntegration < Minitest::Test
  def setup
    @transports = []
  end

  def teardown
    @transports.each do |transport|
      transport.disconnect if transport&.connected?
    end
    @transports.clear
  end

  def test_message_publishing_with_no_discovered_nodes
    transport = create_transport(node_id: "isolated-node")

    # Should not raise error even with no nodes
    message = { test: "data" }.to_json
    transport.send(:do_publish, "TestMessage", message)
    assert true  # If we got here, no exception was raised
  end

  def test_publish_to_nodes_with_mixed_results
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 },
      "node2" => { ip: "192.168.1.11", port: 9999 }
    })

    # Mock sender
    send_count = 0
    mock_sender = Object.new
    mock_sender.define_singleton_method(:send_to_node) do |node_id, data, **options|
      send_count += 1
      raise "Connection failed" if node_id == "node1"
      true
    end

    transport.instance_variable_set(:@sender, mock_sender)

    message = { test: "data" }.to_json

    # Should handle partial failures gracefully
    transport.send(:publish_to_nodes, ["node1", "node2"], "TestMessage", message)
    assert_equal 2, send_count
  end

  def test_subscribe_registers_handler
    transport = create_transport
    handler = ->(msg) { puts msg }

    # Mock dispatcher
    mock_dispatcher = OpenStruct.new(subscribers: Hash.new { |h, k| h[k] = [] })
    transport.instance_variable_set(:@dispatcher, mock_dispatcher)

    # Subscribe
    transport.subscribe("TestMessage", handler)
    handlers = transport.instance_variable_get(:@message_handlers)
    assert handlers.key?("TestMessage")
  end

  def test_handle_smart_message_with_no_subscribers
    transport = create_transport

    message = {
      type: "smart_message",
      message_class: "UnknownMessage",
      payload: { data: "test" }.to_json
    }

    sender_info = { ip: "192.168.1.100", port: 9999 }

    # Should not raise error for unknown message types
    transport.send(:handle_smart_message, message, sender_info)
    assert true  # If we got here, no exception was raised
  end

  def test_handle_smart_message_with_string_keys
    transport = create_transport
    transport.instance_variable_set(:@message_handlers, { "TestMessage" => true })

    # Mock receive method
    received_payload = nil
    transport.define_singleton_method(:receive) do |msg_class, payload|
      received_payload = payload
    end

    message = {
      "type" => "smart_message",
      "message_class" => "TestMessage",
      "payload" => '{"data":"test"}'
    }

    sender_info = { "ip" => "192.168.1.100", "port" => 9999 }

    transport.send(:handle_smart_message, message, sender_info)
    assert_equal '{"data":"test"}', received_payload
  end

  def test_handle_smart_message_with_symbol_keys
    transport = create_transport
    transport.instance_variable_set(:@message_handlers, { "TestMessage" => true })

    received_payload = nil
    transport.define_singleton_method(:receive) do |msg_class, payload|
      received_payload = payload
    end

    message = {
      type: "smart_message",
      message_class: "TestMessage",
      payload: '{"data":"test"}'
    }

    sender_info = { ip: "192.168.1.100", port: 9999 }

    transport.send(:handle_smart_message, message, sender_info)
    assert_equal '{"data":"test"}', received_payload
  end

  def test_heartbeat_from_unknown_node
    transport = create_transport

    message = {
      node_id: "new-node",
      timestamp: Time.now.to_f,
      message_types: ["Message1", "Message2"]
    }

    sender_info = { ip: "192.168.1.50", port: 9999 }

    transport.send(:handle_heartbeat, message, sender_info)

    # Should add new node to registry
    assert_includes transport.node_registry.keys, "new-node"
    assert_equal "192.168.1.50", transport.node_registry["new-node"][:ip]
    assert_equal ["Message1", "Message2"], transport.node_registry["new-node"][:message_types]
  end

  def test_heartbeat_without_node_id
    transport = create_transport

    message = {
      timestamp: Time.now.to_f,
      message_types: []
    }

    sender_info = { ip: "192.168.1.50", port: 9999 }

    # Should not raise error
    transport.send(:handle_heartbeat, message, sender_info)

    # Should not add any nodes
    assert_empty transport.node_registry
  end

  def test_determine_target_nodes_with_invalid_json
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 },
      "node2" => { ip: "192.168.1.11", port: 9999 }
    })

    # Invalid JSON should fall back to broadcasting to all nodes
    invalid_json = "not valid json{{"
    targets = transport.send(:determine_target_nodes, "TestMessage", invalid_json)

    assert_equal ["node1", "node2"], targets.sort
  end

  def test_determine_target_nodes_with_nonexistent_target
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 },
      "node2" => { ip: "192.168.1.11", port: 9999 }
    })

    message = { _sm_header: { to: "nonexistent-node" } }.to_json
    targets = transport.send(:determine_target_nodes, "TestMessage", message)

    # Should return empty array for nonexistent target
    assert_empty targets
  end

  def test_determine_target_nodes_with_partial_capability_match
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, capabilities: ["storage"] },
      "node2" => { ip: "192.168.1.11", port: 9999, capabilities: ["compute"] },
      "node3" => { ip: "192.168.1.12", port: 9999, capabilities: ["storage", "compute"] }
    })

    # Require both capabilities
    message = { _sm_header: { capabilities: ["storage", "compute"] } }.to_json
    targets = transport.send(:determine_target_nodes, "TestMessage", message)

    # Only node3 has both capabilities
    assert_equal ["node3"], targets
  end

  def test_determine_target_nodes_with_empty_capabilities
    transport = create_transport
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, capabilities: ["storage"] },
      "node2" => { ip: "192.168.1.11", port: 9999, capabilities: [] }
    })

    message = { _sm_header: { capabilities: [] } }.to_json
    targets = transport.send(:determine_target_nodes, "TestMessage", message)

    # Empty capabilities should return all nodes
    assert_equal ["node1", "node2"], targets.sort
  end

  def test_cleanup_with_all_stale_nodes
    transport = create_transport(heartbeat_interval: 10.0)

    very_old_time = Time.now - 200

    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, last_seen: very_old_time },
      "node2" => { ip: "192.168.1.11", port: 9999, last_seen: very_old_time }
    })

    transport.instance_variable_set(:@node_registry, {
      "node1" => { last_heartbeat: very_old_time },
      "node2" => { last_heartbeat: very_old_time }
    })

    transport.send(:cleanup_stale_nodes)

    assert_empty transport.discovered_nodes
    assert_empty transport.node_registry
  end

  def test_cleanup_with_no_stale_nodes
    transport = create_transport(heartbeat_interval: 10.0)

    recent_time = Time.now - 5

    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, last_seen: recent_time },
      "node2" => { ip: "192.168.1.11", port: 9999, last_seen: recent_time }
    })

    original_count = transport.discovered_nodes.count

    transport.send(:cleanup_stale_nodes)

    assert_equal original_count, transport.discovered_nodes.count
  end

  def test_network_topology_with_complex_state
    transport = create_transport(node_id: "test-node")

    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, last_seen: Time.now },
      "node2" => { ip: "192.168.1.11", port: 9999, last_seen: Time.now }
    })

    transport.instance_variable_set(:@node_registry, {
      "node1" => { last_heartbeat: Time.now, message_types: ["Msg1"] }
    })

    transport.instance_variable_set(:@message_handlers, {
      "TestMessage" => true,
      "AnotherMessage" => true
    })

    topology = transport.network_topology

    assert_equal "test-node", topology[:local_node]
    assert_equal 2, topology[:discovered_nodes].count
    assert_equal 1, topology[:node_registry].count
    assert_equal 2, topology[:active_subscriptions].count
  end

  def test_disconnect_with_no_sender_or_receiver
    transport = create_transport

    # Ensure sender and receiver are nil
    transport.instance_variable_set(:@sender, nil)
    transport.instance_variable_set(:@receiver, nil)

    # Should not raise error
    transport.disconnect
    assert true  # If we got here, no exception was raised
  end

  def test_disconnect_kills_threads
    transport = create_transport

    # Create mock threads
    mock_discovery = Thread.new { sleep 1000 }
    mock_heartbeat = Thread.new { sleep 1000 }

    transport.instance_variable_set(:@discovery_thread, mock_discovery)
    transport.instance_variable_set(:@heartbeat_thread, mock_heartbeat)

    transport.disconnect

    # Give threads a moment to be killed
    sleep 0.1

    refute mock_discovery.alive?
    refute mock_heartbeat.alive?
  end

  def test_connected_status_with_dead_discovery_thread
    transport = create_transport

    mock_sender = Object.new
    mock_receiver = Object.new
    mock_thread = Thread.new { }

    # Let thread die
    sleep 0.1

    transport.instance_variable_set(:@sender, mock_sender)
    transport.instance_variable_set(:@receiver, mock_receiver)
    transport.instance_variable_set(:@discovery_thread, mock_thread)
    transport.instance_variable_set(:@shutdown, false)

    refute transport.connected?
  end

  def test_handle_incoming_message_with_malformed_data
    transport = create_transport

    # Missing type field
    message = { data: "some data" }
    sender_info = { ip: "192.168.1.100", port: 9999 }

    # Should not raise error
    transport.send(:handle_incoming_message, message, sender_info)
    assert true  # If we got here, no exception was raised
  end

  def test_handle_incoming_message_routes_correctly
    transport = create_transport

    heartbeat_called = false
    transport.define_singleton_method(:handle_heartbeat) do |msg, sender|
      heartbeat_called = true
    end

    smart_message_called = false
    transport.define_singleton_method(:handle_smart_message) do |msg, sender|
      smart_message_called = true
    end

    # Test heartbeat routing
    heartbeat_msg = { type: "heartbeat", node_id: "test" }
    transport.send(:handle_incoming_message, heartbeat_msg, {})
    assert heartbeat_called

    # Test smart_message routing
    smart_msg = { type: "smart_message", message_class: "Test" }
    transport.send(:handle_incoming_message, smart_msg, {})
    assert smart_message_called
  end

  def test_version_constant_accessible
    assert defined?(SmartMessage::Transport::Lanet::VERSION)
    assert_kind_of String, SmartMessage::Transport::Lanet::VERSION
  end

  def test_version_through_lanet_version_module
    assert defined?(SmartMessage::Transport::LanetVersion::VERSION)
    assert_equal SmartMessage::Transport::LanetVersion::VERSION,
                 SmartMessage::Transport::Lanet::VERSION
  end

  private

  def create_transport(**options)
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

      @transports << transport
      transport
    end
  end
end
