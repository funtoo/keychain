#!/bin/bash
V=1.5
mkdir keychain-${V}; cp keychain README ChangeLog keychain-${V}
chown -R root.root keychain-${V}
tar cjvf keychain-${V}.tar.bz2 keychain-${V}
