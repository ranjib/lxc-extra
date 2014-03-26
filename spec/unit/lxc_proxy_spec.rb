require 'spec_helper'
require 'lxc/extra/channel'
require 'lxc/extra/proxy_client_side'
require 'lxc/extra/proxy_server_side'
require 'lxc/extra/selector'
require 'socket'

describe 'LXC proxy' do

  before(:all) do
    c = LXC::Container.new('test')
    c.create('ubuntu') unless c.defined?
    c.start unless c.running?
  end

  def rescue_me(&block)
    begin
      block.call
    rescue
      STDERR.puts "ERROR in thread: #{$!}"
      STDERR.puts $!.backtrace.join("\n")
      raise
    end
  end

  def safe_thread(&block)
    Thread.new do
      rescue_me(&block)
    end
  end

  it 'proxy server receives multiple connections and passes data back and forth' do
    container = LXC::Container.new('test')

    threads = []
    pids = []
    begin
      # Forward 127.0.0.1:80 in the container to google.com from the host
      channel = LXC::Extra::Channel.new
      pids << container.attach do
        rescue_me do
          server = TCPServer.new('127.0.0.1', 5559)
          proxy = LXC::Extra::ProxyClientSide.new(channel, server)
          proxy.start
        end
      end

      # Here is the proxy server
      threads << safe_thread do
        proxy = LXC::Extra::ProxyServerSide.new(channel) do
          TCPSocket.new('127.0.0.1', 9995)
        end
        proxy.start
      end

      # Here is the real TCP server (listener)
      real_server = TCPServer.new('127.0.0.1', 9995)
      threads << safe_thread do
        selector = LXC::Extra::Selector.new
        selector.on_select(real_server) do |server|
          socket = server.accept
          selector.on_select(socket) do |socket|
            message, *other = socket.recvmsg
            if message.size == 0
              selector.delete(socket)
            else
              socket.sendmsg((message.to_i*2).to_s)
            end
          end
        end
        selector.main_loop
      end

      channel2 = LXC::Extra::Channel.new
      # Let's open up a client in the container!
      container.execute do
        rescue_me do
          socket = TCPSocket.new('127.0.0.1', 5559)
          socket.sendmsg('10')
          response, *other = socket.recvmsg
          channel2.send_message(response)
          socket.sendmsg('30')
          response, *other = socket.recvmsg
          channel2.send_message(response)
          socket.close
        end
      end
      container.execute do
        rescue_me do
          socket = TCPSocket.new('127.0.0.1', 5559)
          socket.sendmsg('50')
          response, *other = socket.recvmsg
          channel2.send_message(response)
          socket.sendmsg('70')
          response, *other = socket.recvmsg
          channel2.send_message(response)
          socket.close
        end
      end
      expect(channel2.next).to eq(['20'])
      expect(channel2.next).to eq(['60'])
      expect(channel2.next).to eq(['100'])
      expect(channel2.next).to eq(['140'])
    ensure
      threads.each do |t|
        t.kill
      end
      pids.each do |pid|

        Process.kill(9, pid)
      end
    end
  end
end
