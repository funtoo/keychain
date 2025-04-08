IMPORTANT - GitHub Contributors
===============================

Please apply your patches to `keychain.sh`, *not* the generated `keychain`
script, which we are now including in the git repo to facilitate the
distribution of release archives directly from GitHub. All development work will 
be done on the 'devel' branch and will only be merged into the master branch when 
a new release is made. This should allow the generated files (keychain, man pages,
spec file) to remain in sync on the master branch but no guarantees are made except
for the tagged release. They will be regenerated for official release archives 
only (those tagged with the release version). Anyone using or contributing to the
'devel' branch should assume the generated files are out of date and regenerate 
locally if needed.
Thanks!



Introduction to Keychain
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


