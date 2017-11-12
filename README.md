IMPORTANT - GitHub Contributors
===============================

Please apply your patches to `keychain.sh`, *not* the generated `keychain`
script, which we are now including in the git repo to facilitate the
distribution of release archives direct from GitHub. The file `keychain` and
related generated file (man pages, spec file) may be out-of-date during active
development. We will regenerate them for official release archives only (those
tagged with the release version.) Thanks!

Please submit Introduction to Keychain
========================

**Official documentation for Keychain can be found on [the official Keychain
wiki page](http://www.funtoo.org/Keychain).**

`Keychain` helps you to manage ssh and GPG keys in a convenient and secure
manner. It acts as a frontend to `ssh-agent` and `ssh-add`, but allows you
to easily have one long running `ssh-agent` process per system, rather than
the norm of one `ssh-agent` per login session. 

This dramatically reduces the number of times you need to enter your
passphrase. With `keychain`, you only need to enter a passphrase once every
time your local machine is rebooted. `Keychain` also makes it easy for remote
cron jobs to securely "hook in" to a long running `ssh-agent` process,
allowing your scripts to take advantage of key-based logins.


