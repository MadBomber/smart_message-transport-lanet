# frozen_string_literal: true

require "test_helper"

class SmartMessage::Transport::TestLanetConcurrency < Minitest::Test
  def setup
    @transport = create_transport
  end

  def teardown
    @transport.disconnect if @transport&.connected?
  end

  def test_concurrent_node_discovery_updates
    transport = create_transport

    threads = []
    errors = []

    # Simulate concurrent node discoveries
    10.times do |i|
      threads << Thread.new do
        begin
          discovered = transport.instance_variable_get(:@discovered_nodes)
          discovered["node#{i}"] = {
            ip: "192.168.1.#{i}",
            port: 9999,
            last_seen: Time.now
          }
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors, "Expected no errors, got: #{errors}"
    assert_operator transport.discovered_nodes.count, :>=, 1
  end

  def test_concurrent_heartbeat_handling
    transport = create_transport

    threads = []
    errors = []

    # Simulate concurrent heartbeats from different nodes
    20.times do |i|
      threads << Thread.new do
        begin
          message = {
            node_id: "node#{i}",
            timestamp: Time.now.to_f,
            message_types: ["TestMessage"]
          }

          sender_info = {
            ip: "192.168.1.#{i % 255}",
            port: 9999
          }

          transport.send(:handle_heartbeat, message, sender_info)
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    assert_operator transport.node_registry.count, :>=, 1
  end

  def test_concurrent_message_handler_registration
    transport = create_transport

    threads = []
    errors = []

    # Multiple threads registering handlers
    10.times do |i|
      threads << Thread.new do
        begin
          transport.send(:register_message_handler, "Message#{i % 5}")
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    handlers = transport.instance_variable_get(:@message_handlers)
    assert_operator handlers.count, :>=, 1
  end

  def test_concurrent_target_determination
    transport = create_transport

    # Populate with some nodes
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 },
      "node2" => { ip: "192.168.1.11", port: 9999 },
      "node3" => { ip: "192.168.1.12", port: 9999 }
    })

    threads = []
    results = []
    errors = []

    # Multiple threads determining targets concurrently
    20.times do
      threads << Thread.new do
        begin
          message = { test: "data" }.to_json
          targets = transport.send(:determine_target_nodes, "TestMessage", message)
          results << targets
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    assert_equal 20, results.count
    # All results should be consistent
    results.each do |targets|
      assert_equal 3, targets.count
    end
  end

  def test_concurrent_cleanup_and_discovery
    transport = create_transport(heartbeat_interval: 0.1)

    old_time = Time.now - 100
    recent_time = Time.now

    transport.instance_variable_set(:@discovered_nodes, {
      "stale_node" => { ip: "192.168.1.10", port: 9999, last_seen: old_time },
      "active_node" => { ip: "192.168.1.11", port: 9999, last_seen: recent_time }
    })

    threads = []
    errors = []

    # One thread cleaning up
    threads << Thread.new do
      begin
        5.times do
          transport.send(:cleanup_stale_nodes)
          sleep 0.01
        end
      rescue => e
        errors << e
      end
    end

    # Another thread adding new nodes
    threads << Thread.new do
      begin
        5.times do |i|
          discovered = transport.instance_variable_get(:@discovered_nodes)
          discovered["new_node#{i}"] = {
            ip: "192.168.1.#{100 + i}",
            port: 9999,
            last_seen: Time.now
          }
          sleep 0.01
        end
      rescue => e
        errors << e
      end
    end

    threads.each(&:join)

    assert_empty errors
    refute_includes transport.discovered_nodes.keys, "stale_node"
  end

  def test_concurrent_network_topology_reads
    transport = create_transport

    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999 }
    })

    threads = []
    topologies = []
    errors = []

    # Multiple threads reading topology concurrently
    10.times do
      threads << Thread.new do
        begin
          topologies << transport.network_topology
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    assert_equal 10, topologies.count
    # All topologies should be valid
    topologies.each do |topo|
      assert_kind_of Hash, topo
      assert_includes topo, :local_node
      assert_includes topo, :discovered_nodes
    end
  end

  def test_concurrent_message_handling
    transport = create_transport
    transport.instance_variable_set(:@message_handlers, { "TestMessage" => true })

    received_count = 0
    mutex = Mutex.new

    transport.define_singleton_method(:receive) do |msg_class, payload|
      mutex.synchronize { received_count += 1 }
    end

    threads = []
    errors = []

    # Multiple threads handling messages concurrently
    20.times do |i|
      threads << Thread.new do
        begin
          message = {
            type: "smart_message",
            message_class: "TestMessage",
            payload: "{\"id\":#{i}}"
          }

          sender_info = { ip: "192.168.1.100", port: 9999 }

          transport.send(:handle_smart_message, message, sender_info)
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    assert_equal 20, received_count
  end

  def test_concurrent_disconnect_operations
    # Create multiple transports
    transports = 5.times.map { create_transport(node_id: "node#{rand(1000)}") }

    threads = []
    errors = []

    # Disconnect all concurrently
    transports.each do |transport|
      threads << Thread.new do
        begin
          transport.disconnect
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
  end

  def test_register_and_unregister_handlers_concurrently
    transport = create_transport

    threads = []
    errors = []

    # Some threads registering, some unregistering
    20.times do |i|
      threads << Thread.new do
        begin
          if i.even?
            transport.send(:register_message_handler, "Message#{i % 5}")
          else
            transport.send(:unregister_message_handler, "Message#{i % 5}")
          end
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    # Should complete without deadlock or crashes
  end

  def test_concurrent_reads_and_writes_to_discovered_nodes
    transport = create_transport

    # Initialize with some nodes
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, last_seen: Time.now }
    })

    threads = []
    errors = []
    read_results = []

    # Reader threads
    10.times do
      threads << Thread.new do
        begin
          10.times do
            nodes = transport.discovered_nodes.dup
            read_results << nodes.count
            sleep 0.001
          end
        rescue => e
          errors << e
        end
      end
    end

    # Writer threads
    5.times do |i|
      threads << Thread.new do
        begin
          10.times do |j|
            discovered = transport.instance_variable_get(:@discovered_nodes)
            discovered["node#{i}_#{j}"] = {
              ip: "192.168.1.#{(i * 10 + j) % 255}",
              port: 9999,
              last_seen: Time.now
            }
            sleep 0.001
          end
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    assert_operator read_results.count, :>, 0
  end

  def test_stress_test_rapid_heartbeats
    transport = create_transport

    threads = []
    errors = []
    success_count = 0
    mutex = Mutex.new

    # Rapid heartbeats from many nodes
    50.times do |i|
      threads << Thread.new do
        begin
          10.times do
            message = {
              node_id: "node#{i}",
              timestamp: Time.now.to_f,
              message_types: ["Msg1", "Msg2"]
            }

            sender_info = { ip: "192.168.1.#{i % 255}", port: 9999 }

            transport.send(:handle_heartbeat, message, sender_info)

            mutex.synchronize { success_count += 1 }
          end
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    assert_equal 500, success_count
  end

  def test_concurrent_capability_based_routing
    transport = create_transport

    # Set up nodes with different capabilities
    transport.instance_variable_set(:@discovered_nodes, {
      "node1" => { ip: "192.168.1.10", port: 9999, capabilities: ["storage"] },
      "node2" => { ip: "192.168.1.11", port: 9999, capabilities: ["compute"] },
      "node3" => { ip: "192.168.1.12", port: 9999, capabilities: ["storage", "compute"] }
    })

    threads = []
    results = []
    errors = []

    # Multiple threads routing based on capabilities
    20.times do |i|
      threads << Thread.new do
        begin
          cap = i.even? ? ["storage"] : ["compute"]
          message = { _sm_header: { capabilities: cap } }.to_json

          targets = transport.send(:determine_target_nodes, "TestMessage", message)
          results << { capabilities: cap, targets: targets }
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
    assert_equal 20, results.count

    # Verify routing logic was correct for each
    results.each do |result|
      if result[:capabilities] == ["storage"]
        assert_includes result[:targets], "node1"
        assert_includes result[:targets], "node3"
      else
        assert_includes result[:targets], "node2"
        assert_includes result[:targets], "node3"
      end
    end
  end

  def test_mixed_operations_stress_test
    transport = create_transport

    threads = []
    errors = []

    # Mix of different operations
    30.times do |i|
      threads << Thread.new do
        begin
          case i % 3
          when 0
            # Add nodes
            discovered = transport.instance_variable_get(:@discovered_nodes)
            discovered["node#{i}"] = {
              ip: "192.168.1.#{i % 255}",
              port: 9999,
              last_seen: Time.now
            }
          when 1
            # Read topology
            transport.network_topology
          when 2
            # Handle heartbeat
            message = { node_id: "node#{i}", timestamp: Time.now.to_f }
            sender_info = { ip: "192.168.1.#{i % 255}", port: 9999 }
            transport.send(:handle_heartbeat, message, sender_info)
          end
        rescue => e
          errors << e
        end
      end
    end

    threads.each(&:join)

    assert_empty errors
  end

  private

  def create_transport(**options)
    SmartMessage::Transport::Lanet.allocate.tap do |transport|
      default_options = {
        port: 9999,
        broadcast_port: 9998,
        node_id: "test-node-#{rand(10000)}",
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
