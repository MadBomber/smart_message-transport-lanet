# SmartMessage::Transport::Lanet

A SmartMessage transport adapter that enables peer-to-peer message communication over local area networks using the [Lanet](https://github.com/MadBomber/lanet) library. This transport provides automatic node discovery, heartbeat monitoring, and capability-based message routing for distributed systems on LANs.

## Features

- **Automatic Node Discovery**: Discovers peers on the local network automatically
- **Peer-to-Peer Messaging**: Direct communication between nodes without central broker
- **Heartbeat Monitoring**: Automatic health checks and stale node cleanup
- **Capability-Based Routing**: Route messages to nodes based on their capabilities
- **Targeted & Broadcast Messaging**: Send to specific nodes or broadcast to all
- **Network Topology Visibility**: Monitor discovered nodes and active subscriptions
- **Thread-Safe Operations**: Concurrent message handling with background services
- **Configurable via Environment**: Easy configuration through environment variables

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'smart_message-transport-lanet'
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install smart_message-transport-lanet
```

## Usage

### Basic Setup

```ruby
require 'smart_message'
require 'smart_message/transport/lanet'

# Define your message class
class ChatMessage < SmartMessage::Base
  attribute :username, :string
  attribute :message, :string
  attribute :timestamp, :time
end

# Configure the transport
transport = SmartMessage::Transport::Lanet.new(
  node_id: "chat-server-1",
  port: 9999,
  broadcast_port: 9998
)

# Connect to the network
transport.connect

# Subscribe to messages
transport.subscribe(ChatMessage, ->(msg) {
  puts "[#{msg.timestamp}] #{msg.username}: #{msg.message}"
})

# Publish a message
message = ChatMessage.new(
  username: "alice",
  message: "Hello, network!",
  timestamp: Time.now
)
transport.publish(message)
```

### Configuration Options

Configure the transport using options or environment variables:

```ruby
transport = SmartMessage::Transport::Lanet.new(
  # Network settings
  port: 9999,                      # ENV: LANET_PORT
  broadcast_port: 9998,            # ENV: LANET_BROADCAST_PORT
  network_interface: "eth0",       # ENV: LANET_NETWORK_INTERFACE

  # Node identification
  node_id: "my-service-1",         # ENV: LANET_NODE_ID (default: hostname)

  # Security
  encryption_key: "your-key",      # ENV: LANET_ENCRYPTION_KEY
  signing_key: "your-sig-key",     # ENV: LANET_SIGNING_KEY

  # Timing
  discovery_timeout: 5.0,          # ENV: LANET_DISCOVERY_TIMEOUT (seconds)
  connection_timeout: 10.0,        # ENV: LANET_CONNECTION_TIMEOUT (seconds)
  heartbeat_interval: 30.0,        # ENV: LANET_HEARTBEAT_INTERVAL (seconds)

  # Message settings
  max_message_size: 1048576,       # ENV: LANET_MAX_MESSAGE_SIZE (bytes, 1MB default)
  enable_compression: true         # ENV: LANET_ENABLE_COMPRESSION
)
```

### Environment Variable Configuration

```bash
export LANET_PORT=9999
export LANET_BROADCAST_PORT=9998
export LANET_NODE_ID=my-service
export LANET_ENCRYPTION_KEY=my-secret-key
export LANET_HEARTBEAT_INTERVAL=30.0
```

### Targeted Messaging

Send messages to specific nodes by including routing information in the message header:

```ruby
# Send to a specific node
message = ChatMessage.new(
  username: "alice",
  message: "Private message"
)
message.header[:to] = "chat-server-2"
transport.publish(message)

# Broadcast to all nodes
message.header[:to] = "broadcast"
transport.publish(message)
```

### Capability-Based Routing

Route messages to nodes with specific capabilities:

```ruby
# Send to nodes with "storage" capability
message = DataMessage.new(data: large_dataset)
message.header[:capabilities] = ["storage"]
transport.publish(message)

# Send to nodes with multiple capabilities
message.header[:capabilities] = ["compute", "gpu"]
transport.publish(message)
```

### Network Topology

Monitor the network topology and discovered nodes:

```ruby
topology = transport.network_topology

puts "Local Node: #{topology[:local_node]}"
puts "Discovered Nodes: #{topology[:discovered_nodes].count}"
puts "Active Subscriptions: #{topology[:active_subscriptions]}"

topology[:discovered_nodes].each do |node_id, info|
  puts "  #{node_id}: #{info[:ip]}:#{info[:port]}"
  puts "    Last seen: #{info[:last_seen]}"
  puts "    Capabilities: #{info[:capabilities].join(', ')}"
end
```

### Manual Node Discovery

Trigger node discovery manually:

```ruby
transport.discover_nodes!
```

### Disconnecting

Properly disconnect from the network:

```ruby
transport.disconnect
```

## Architecture

The Lanet transport uses three main background services:

1. **Discovery Service**: Periodically broadcasts presence and discovers other nodes
2. **Heartbeat Service**: Sends periodic health checks and cleans up stale nodes
3. **Message Receiver**: Listens for incoming messages and routes them to subscribers

### Message Flow

```
Publisher                Transport               Receiver
   |                         |                      |
   |--publish(message)------>|                      |
   |                         |--serialize---------->|
   |                         |--determine_targets-->|
   |                         |--send_to_nodes------>|
   |                         |                      |--deserialize-->
   |                         |                      |--dispatch----->Handler
```

### Node Discovery

```
Node A                  Network                 Node B
  |                         |                      |
  |--broadcast(presence)--->|-------------------->|
  |                         |                      |
  |<--------------------acknowledge<--------------|
  |                         |                      |
  |--heartbeat------------->|-------------------->|
  |                         |                      |
```

## Use Cases

### Distributed Chat System

```ruby
# Server node
transport = SmartMessage::Transport::Lanet.new(node_id: "chat-server")
transport.connect
transport.subscribe(ChatMessage, method(:handle_chat))
```

### IoT Sensor Network

```ruby
# Sensor node (publishes)
sensor = SmartMessage::Transport::Lanet.new(node_id: "sensor-#{id}")
sensor.connect

loop do
  reading = SensorReading.new(
    sensor_id: id,
    temperature: read_temperature,
    humidity: read_humidity
  )
  sensor.publish(reading)
  sleep 60
end

# Collector node (subscribes)
collector = SmartMessage::Transport::Lanet.new(node_id: "collector")
collector.connect
collector.subscribe(SensorReading, method(:store_reading))
```

### Distributed Task Processing

```ruby
# Worker node with capabilities
worker = SmartMessage::Transport::Lanet.new(
  node_id: "worker-#{id}",
  capabilities: ["compute", "video-processing"]
)
worker.connect
worker.subscribe(Task, method(:process_task))

# Coordinator node
coordinator = SmartMessage::Transport::Lanet.new(node_id: "coordinator")
coordinator.connect

task = Task.new(type: "video-transcode", file: "movie.mp4")
task.header[:capabilities] = ["video-processing"]
coordinator.publish(task)
```

## Thread Safety

The Lanet transport is thread-safe and handles concurrent operations:

- Background discovery runs in a dedicated thread
- Background heartbeat runs in a dedicated thread
- Message receiving happens in a dedicated thread
- Message handlers are called in the subscriber's context

## Error Handling

The transport handles errors gracefully:

- Failed node connections are logged and retried
- Stale nodes are automatically cleaned up
- Discovery failures don't interrupt operation
- Heartbeat failures are logged but don't stop the service

## Logging

Configure logging through the SmartMessage logger:

```ruby
transport = SmartMessage::Transport::Lanet.new(
  logger: Logger.new($stdout, level: Logger::DEBUG)
)
```

Log messages are prefixed with `[Lanet]` for easy filtering.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt.

To install this gem onto your local machine, run `bundle exec rake install`.

## Testing

Run the test suite:

```bash
bundle exec rake test
```

Run RuboCop for style checking:

```bash
bundle exec rake rubocop
```

Run all checks:

```bash
bundle exec rake
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/smart_message-transport-lanet.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`rake test`)
5. Ensure code style compliance (`rake rubocop`)
6. Commit your changes (`git commit -am 'feat: add some feature'`)
7. Push to the branch (`git push origin feature/my-feature`)
8. Create a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Credits

- Built on top of [SmartMessage](https://github.com/MadBomber/smart_message)
- Uses [Lanet](https://github.com/MadBomber/lanet) for P2P communication
- Maintained by [Dewayne VanHoozer](mailto:dewayne@vanhoozer.me)
