#!/bin/bash
V=1.0
mkdir keychain-${V}; cp keychain keychain-${V}
chown -R root.root keychain-${V}
tar cjvf keychain-${V}.tar.bz2 keychain-${V}
