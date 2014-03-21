module LXC
  module Extra
    #
    # Proxy server that listens for connections on the client side and sends
    # the data to the corresponding LXCProxyServerSide through an LXCChannel.
    #
    # == Usage
    #
    #   # Forward 127.0.0.1:80 in the container to google.com from the host
    #   channel = LXC::Extra::LXCChannel.new
    #   pid = container.attach do
    #     server = TCPServer.new('127.0.0.1', 5559)
    #     proxy = LXC::Extra::LXCProxyClientSide.new(channel, server)
    #     proxy.start
    #   end
    #
    #   # Here is the proxy server
    #   proxy = LXC::Extra::LXCProxyServerSide.new(channel) do
    #     TCPSocket.new('127.0.0.1', 9995)
    #   end
    #   proxy.start
    #
    class LXCProxyClientSide
      #
      # Create a new LXCProxyClientSide.
      #
      # == Arguments
      # channel:: LXCChannel to communicate over
      # listen_server:: TCPServer to listen to
      #
      def initialize(channel, listen_server)
        @channel = channel
        @listen_server = listen_server
        @sockets = {}
      end

      attr_reader :channel
      attr_reader :listen_server

      #
      # Start forwarding connections and data.  This call will not return until
      # stop is called.
      #
      def start
        begin
          begin
            @selector = Selector.new
            @selector.on_select(@listen_server, &method(:on_server_accept))
            @selector.on_select(@channel.read_fd, &method(:on_channel_response))
            @selector.main_loop
          ensure
            @sockets.values.each { |socket| socket.close }
            @sockets = {}
            @selector = nil
          end
        rescue
          STDERR.puts("Proxy server error on client side: #{$!}\n#{$!.backtrace.join("\n")}")
          @channel.send_message(:server_error, $!)
          raise
        end
      end

      #
      # Stop forwarding connections and data.  Existing connections will be closed
      # and a stop message will be sent to the other side.
      #
      def stop
        @sockets.values.each { |socket| socket.close }
        @sockets = {}
        @selector = nil
        @channel.send_message(:stop)
      end

      private

      def on_server_accept(server)
        socket = server.accept
        @selector.on_select(socket, &method(:on_client_data))
        @sockets[socket.fileno] = socket
        @channel.send_message(:open, socket.fileno)
      end

      def on_client_data(socket)
        message, *args = socket.recvmsg
        if message.length == 0
          @channel.send_message(:close, socket.fileno)
          @selector.delete(socket)
          @sockets.delete(socket.fileno)
          socket.close
        else
          @channel.send_message(:data, socket.fileno, message)
        end
      end

      def on_channel_response(read_fd)
        message_type, fileno, *args = @channel.next(:stop)
        begin
          case message_type
          when :data
            @sockets[fileno].sendmsg(args[0])
          when :close, :connection_error
            @sockets[fileno].close
            @selector.delete(@sockets[fileno])
            @sockets.delete(fileno)
          when :stop, :server_error
            return :stop
          else
            raise "Unknown message type #{message_type} passed from server to client side proxy"
          end
        rescue
          STDERR.puts("Error in on_channel_response: #{$!}\n#{$!.backtrace.join("\n")}")
          if fileno
            @server.send_message(:connection_error, fileno, $!) unless message_type == :close || message_type == :connection_error
            socket = @sockets[fileno]
            if socket
              socket.close
              @selector.delete(socket)
            end
            @sockets.delete(fileno)
          end
        end
      end
    end
  end
end
