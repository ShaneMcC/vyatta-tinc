Tinc configuration templates and scripts for vyatta.

Prereqs for building: `sudo apt-get install build-essential devscripts debhelper autotools-dev autoconf fakeroot automake` on a debian/ubuntu box

Building: `debuild -us -uc` then scp ../vyatta-tinc_1.0.0_all.deb to your vyatta device.

Usage: Install `tinc` manually hand via apt, then install vyatta-tinc using `dpkg -i` - config settings will be available under `protocols tinc`.

Be aware, that any time the tinc config is changed, /etc/tinc will be deleted and rebuilt based on the vyatta config, and any manual changes will be deleted.
