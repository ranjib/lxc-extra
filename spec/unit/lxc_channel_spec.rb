require 'spec_helper'
require 'lxc/extra/channel'

describe LXC::Extra::Channel do

  before(:all) do
    c = LXC::Container.new('test')
    c.create('ubuntu') unless c.defined?
    c.start unless c.running?
  end

  it 'an open channel should successfully pass multiple objects' do
    c = LXC::Container.new('test')
    channel = LXC::Extra::Channel.new
    pid = c.attach do
      begin
        channel.listen do |host, number|
          host.send_message(number+1)
        end
      end
    end
    begin
      results = []
      channel.send_message(1)
      channel.listen do |container, number|
        results << number
        if number > 5
          container.stop
        else
          container.send_message(number)
        end
      end
      Process.waitpid(pid)
    rescue
      Process.kill('KILL', pid)
      raise
    end
    expect(results).to eq([ 2, 3, 4, 5, 6 ])
  end

  it 'container.open_channel works the same as the explicit version' do
    c = LXC::Container.new('test')
    channel, pid = c.open_channel do |host, number|
      host.send_message(number+1)
    end
    begin
      results = []
      channel.send_message(1)
      channel.listen do |container, number|
        results << number
        if number > 5
          container.stop
        else
          container.send_message(number)
        end
      end
      Process.waitpid(pid)
    rescue
      Process.kill('KILL', pid)
      raise
    end
    expect(results).to eq([ 2, 3, 4, 5, 6 ])
  end
end
