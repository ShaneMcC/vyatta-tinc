# vyatta-tinc
## What is it?
Templates and Scripts for vyatta/[vyos](http://vyos.net/)/[edgeos/edgemax](http://www.ubnt.com/) to allow managing [tinc](www.tinc-vpn.org)-based VPN Tunnels.

This has only been tested on Ubiquiti EdgeRouter Lite, but should work on anything that is vyatta-based.

## How to build

At the moment building is only tested on ubuntu, but it should work on debian.

Firstly, install the build-packages:

```
sudo apt-get install build-essential devscripts debhelper autotools-dev autoconf fakeroot automake
```

and then build:
```
debuild -us -uc
```

This will produce a number of files in the ../ directory, the one you care about is called `vyatta-tinc_1.0.0_all.deb` or so. This can then be SCP-ed up to your vyatta device.

## Installation

The fully-built package will only provide the ability to set the configuration, there is still a soft-depends on `tinc` which needs to be installed manually for the configuration to actually do anything, so this will require that the debian repositories have been added to your device.

After `tinc` is installed, you can then install `vyatta-tinc` using `dpkg -i vyatta-tinc_1.0.0_all.deb`

## Usage

Pretty much every config setting should be supported, if I've missed something then let me know by raising an issue against this repo.

One thing to be aware of, any time the tinc config is changed, /etc/tinc will be deleted and rebuilt based on the vyatta config, and any manual changes you have made will be deleted.

## Problems
My own tinc config is pretty simple, and it works fine - but if you find something doesn't work as expected, or is missing (that is related to vyatta-tinc not tinc itself) then please take a look at the [issues page](https://github.com/ShaneMcC/vyatta-tinc/issues) to see if it's a known issue. If not, please raise one to let me know and I'll do what I can to get it resolved. The more information you can give to help reproduce the issue the better.

## Pull Requests
Pull requests are appreciated and welcome!

## Questions
I can be found idling on various different IRC Networks, but the best way to get in touch would be to message "Dataforce" on Quakenet, or drop me a mail (email address is in my [github profile](https://github.com/ShaneMcC))