#!/bin/bash
V=2.0.3
rm -rf /tmp/keychain-${V}
mkdir /tmp/keychain-${V}; cp keychain README ChangeLog keychain.1 COPYING /tmp/keychain-${V}
chown -R root.root /tmp/keychain-${V}
cd /tmp; tar cjvf keychain-${V}.tar.bz2 keychain-${V}
