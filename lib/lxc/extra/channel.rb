module LXC
  module Extra
    #
    # Bidirectional Ruby communications between a host and an LXC container.
    # It handles bidirectional communications: the host can send a message to
    # the container using channel.send_message, and the container can send to
    # the host using channel.send_message as well.
    #
    # This class is intended to be created before ct.attach and used by both
    # the host and the container.
    #
    # == Shorthand Usage
    #
    # require 'lxc'
    # require 'lxc/extra'
    #
    # container = LXC::Container.new('simple')
    # channel, pid = container.open_channel do |host, number|
    #   puts "received #{number} INSIDE!"
    #   if number > 10
    #     host.stop
    #   else
    #     host.send_message(number+1)
    #   end
    # end
    # channel.send_message(1)
    # channel.listen do |container, number|
    #   puts "received #{number} OUTSIDE!"
    #   container.send_message(number+1) unless number > 10
    # end
    #
    # == Extended Usage
    #
    #   channel = Channel.new
    #   ct.attach do
    #     channel.listen do |host, number|
    #       "received #{number} INSIDE!"
    #       if number > 10
    #         host.stop
    #       else
    #         host.send(number+1)
    #       end
    #     end
    #   end
    #   channel.listen do |container, number|
    #     "received #{number} OUTSIDE!"
    #     container.send(number+1)
    #   end
    #
    class Channel
      #
      # Create a new LXC channel.
      #
      def initialize
        @from_container, @to_host = IO.pipe
        @from_host, @to_container = IO.pipe
        @host_pid = Process.pid
      end

      attr_reader :from_container
      attr_reader :to_host
      attr_reader :from_host
      attr_reader :to_container
      attr_reader :host_pid

      #
      # Listen for data from the other side.  Loops until stop is received.
      #
      # == Arguments
      # &block:: callback
      #
      # == Example
      #
      #   channel.listen do |*args|
      #     puts "Received #{args} from the other side."
      #   end
      #
      def listen(&block)
        while true
          args = self.next
          if args.is_a?(Stop)
            return
          end
          block.call(self, *args)
        end
      end

      #
      # Send a message to the other side.
      # You may send arbitrary Ruby, which will be sent with Marshal.dump.
      #
      # == Arguments
      # args:: a list of arguments to send. Arbitrary Ruby objects may be sent.
      #        The other side's listen callback will receive these arguments.
      #
      def send_message(*args)
        Marshal.dump(args, write_fd)
      end

      #
      # Get the next result.
      #
      # == Arguments
      # stop_result:: result to return when the channel wants to shut down.  Defaults to LXC::Extra::Channel::Stop.singleton
      #
      # == Returns
      # Returns nextLXC::Extra::Channel::Stop instance if the channel closes.
      def next(stop_result = Stop.singleton)
        if read_fd.closed?
          stop_result
        else
          Marshal.load(read_fd)
        end
      end

      #
      # Stop the channel.  Sends a message to the other side to stop it, too.
      #
      def stop
        send_message(Stop.singleton)
        @from_container.close
        @to_host.close
        @from_host.close
        @to_container.close
      end

      #
      # Pretend a message was sent from the other side.
      #
      # For debug purposes.
      #
      def pretend_message_was_sent(*args)
        if Process.pid == @host_pid
          Marshal.dump(args, @to_host)
        else
          Marshal.dump(args, @to_container)
        end
      end

      #
      # File descriptor that sends data to the other side.
      #
      def write_fd
        if Process.pid == @host_pid
          @to_container
        else
          @to_host
        end
      end

      #
      # File descriptor that receives data from the other side.
      #
      def read_fd
        if Process.pid == @host_pid
          @from_container
        else
          @from_host
        end
      end

      class Stop
        def self.singleton
          @@singleton ||= Stop.new
        end
      end
    end
  end
end
