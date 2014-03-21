module LXC
  module Extra
    #
    # Provides a way to listen to multiple disparate file descriptors with
    # different callbacks to handle each one.
    #
    # == Example
    #
    #   require 'lxc/extra/selector'
    #   require 'socket'
    #
    #   def repeat_to(socket, selector, out)
    #     message, *other = socket.recvmsg
    #     if message.size == 0
    #       selector.delete(socket)
    #       return
    #     end
    #     out.write(message)
    #   end
    #
    #   selector = LXC::Extra::Selector.new()
    #
    #   # Listen on 20480 and echo output to STDOUT
    #   server = TCPServer.new(20480)
    #   selector.on_select(server) do |server|
    #     socket = server.accept
    #     selector.on_select(socket, selector, STDOUT, &method(:repeat_to))
    #   end
    #
    #   # Listen on 20481 and echo output to STDERR
    #   server = TCPServer.new(2049)
    #   selector.on_select(server) do |server|
    #     socket = server.accept
    #     selector.on_select(socket, selector, STDERR, &method(:repeat_to))
    #   end
    #
    #   # Do all that listening on one thread!
    #   selector.main_loop
    #
    # NOTE: This is not presently thread-safe in that adds and deletes must be
    # done on the same thread as the main_loop.
    #
    class Selector
      #
      # Create a new selector.
      #
      def initialize
        @fd_callbacks = {}
      end

      #
      # Add a file descriptor to listen on.
      #
      # == Arguments
      #
      # fd:: file descriptor to listen on.
      # args:: optional set of arguments to pass to callback
      # callback:: callback to call when file descriptor has data available
      #
      def on_select(fd, *args, &callback)
        @fd_callbacks[fd] = {
          :args => args,
          :callback => callback
        }
      end

      #
      # Stop listening to a file descriptor.
      #
      # == Arguments
      #
      # fd:: file descriptor to stop listening to.
      #
      def delete(fd)
        @fd_callbacks.delete(fd)
      end

      #
      # Listen for any of the given file handles to be ready (with IO.select)
      # and call their callbacks when they are.
      #
      def main_loop
        begin
          while true
            ready = IO.select(@fd_callbacks.keys)
            ready[0].each do |fd|
              callback = @fd_callbacks[fd]
              if callback
                args = [ fd ]
                args += callback[:args] if callback[:args]
                if callback[:callback].call(*args) == :stop
                  return
                end
              end
            end
          end
        rescue
          raise
        end
      end
    end
  end
end
