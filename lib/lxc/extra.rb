require 'lxc'
require 'lxc/extra/version'
require 'io/wait'

module LXC
  module Extra
    def execute(&block)
      r,w = IO.pipe
      ret = attach(wait:true) do
        ENV.clear
        ENV['PATH']='/usr/bin:/bin:/usr/sbin'
        r.close
        begin
          out = block.call
          w.write(Marshal.dump(out))
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
  end
  class Container
    include Extra
  end
end
