# LXC::Extra
Helper methods for ruby lxc binding

## Installation

Add this line to your application's Gemfile:

    gem 'lxc-extra', github: 'ranjib/lxc-extra'

And then execute:

    $ bundle

## Usage
Core [LXC ruby bindings]() exposes liblxc api. LXC::Extra provides few additional methods. For example, the `attach` method
from core lxc allows executing arbitrary ruby code inside a container. Since the `attach` method does so via spawning a child process
inside the container, getting any data back from the attach block requires IPC. LXC::Extra provides `execute` method that wraps the `attach` method
and does the IPC magic for you, using `IO.pipe`.

```ruby
require 'lxc/extra'
ct = LXC::Container.new('test')
data = ct.execute do
        # run some code 
       end
```


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
