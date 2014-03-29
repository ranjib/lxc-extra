require 'lxc'
require 'lxc/extra/version'
require 'lxc/extra/channel'
require 'io/wait'
require 'timeout'

module LXC
  module Extra
    def execute(opts= {}, &block)
      attach_opts = opts[:attach_options] || {}
      attach_opts[:wait] ||= true
      timeout = opts[:timeout] || 3600
      r,w = IO.pipe
      ret = attach(attach_opts) do
        ENV.clear
        ENV['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin'
        ENV['TERM'] = 'xterm-256color'
        ENV['SHELL'] = '/bin/bash'
        r.close
        begin
          Timeout::timeout(timeout) do
            out = block.call
            w.write(Marshal.dump(out))
          end
        rescue Exception => e
          w.write(Marshal.dump(e))
        end
      end
      w.close
      o = nil
      if r.ready?
        o = Marshal.load(r.read)
      end
      r.close
      raise o if o.is_a?(Exception)
      o
    end

    def open_channel(&block)
      channel = ::LXC::Extra::Channel.new
      pid = attach do
        channel.listen(&block)
      end
      [channel, pid]
    end
  end
  class Container
    include Extra
  end
end
