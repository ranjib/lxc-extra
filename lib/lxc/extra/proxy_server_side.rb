require 'lxc/extra/selector'

module LXC
  module Extra
    #
    # Proxy server that listens for connections froom the corresponsing
    # ProxyClientSide and sends them to the actual server.
    #
    # == Usage
    #
    #   # Forward 127.0.0.1:80 in the container to google.com from the host
    #   channel = LXC::Extra::Channel.new
    #   pid = container.attach do
    #     server = TCPServer.new('127.0.0.1', 5559)
    #     proxy = LXC::Extra::ProxyClientSide.new(channel, server)
    #     proxy.start
    #   end
    #
    #   # Here is the proxy server
    #   proxy = LXC::Extra::ProxyServerSide.new(channel) do
    #     TCPSocket.new('127.0.0.1', 9995)
    #   end
    #   proxy.start
    #
    class ProxyServerSide
      #
      # Create a new ProxyServerSide.
      #
      # == Arguments
      # channel: Channel to send/receive connections from the other side.
      # &server_connector:: block that will be called (with no arguments) when the server
      #                     opens a new connection, to create a new connection to the
      #                     server. Must return a socket.
      #
      def initialize(channel, &server_connector)
        @channel = channel
        @server_connector = server_connector
      end

      attr_reader :channel
      attr_reader :server_connector

      #
      # Start forwarding connections from the other side to the server.  Blocks
      # until stop is called.
      #
      def start
        @filenos = {}
        @sockets = {}
        begin
          @selector = Selector.new
          @selector.on_select(channel.read_fd, &method(:on_channel_message))
          @selector.main_loop
        ensure
          @sockets.values.each { |socket| socket.close }
        end
      end

      #
      # Stop forwarding connections and data.  Existing connections will be closed
      # and a stop message will be sent to the other side.
      #
      def stop
        @selector.stop
      end

      private

      def on_channel_message(read_fd)
        message_type, fileno, *args = @channel.next(:stop)
        socket = @sockets[fileno]
        begin
          case message_type
          when :open
            socket = @server_connector.call
            @selector.on_select(socket, &method(:on_server_response))
            @sockets[fileno] = socket
            @filenos[socket] = fileno
          when :data
            socket.sendmsg(args[0])
          when :close, :connection_error
            socket.close
            @selector.delete(socket)
            @filenos.delete(socket)
            @sockets.delete(fileno)
          when :stop, :server_error
            return :stop
          else
            raise "Unknown message type #{message_type} passed from channel to host"
          end
        rescue
          STDERR.puts("Error in on_channel_message: #{$!}\n#{$!.backtrace.join("\n")}")
          if fileno
            @channel.send_message(:connection_error, fileno) unless message_type == :close || message_type == :connection_error
            if socket
              socket.close
              @selector.delete(socket)
              @filenos.delete(socket)
            end
            @sockets.delete(fileno)
          end
        end
      end

      def on_server_response(socket)
        message, *args = socket.recvmsg
        fileno = @filenos[socket]
        if message.length == 0
          socket.close
          if fileno
            @channel.send_message(:close, fileno)
            @sockets.delete(fileno)
          end
          @filenos.delete(socket)
          @selector.delete(socket)
        else
          @channel.send_message(:data, fileno, message)
        end
      end
    end
  end
end
