========================
Introduction to Keychain
========================

:keywords: keychain, funtoo, gentoo, Daniel Robbins
:description: 

        This page contains information about Keychain, an OpenSSH and
        commercial SSH2-compatible RSA/DSA key management application.

:version: 2009-07-26
:author: Daniel Robbins
:contact: drobbins@funtoo.org
:copyright: funtoo
:language: English

Introduction
============

.. _keychain git repository: http://www.github.com/funtoo/keychain
.. _Common Threads\: OpenSSH key management, Part 1: http://www.ibm.com/developerworks/library/l-keyc.html
.. _Common Threads\: OpenSSH key management, Part 2: http://www.ibm.com/developerworks/library/l-keyc2/
.. _Common Threads\: OpenSSH key management, Part 3: http://www.ibm.com/developerworks/library/l-keyc3/
.. _OpenSSH: http://www.openssh.com
.. _funtoo-dev mailing list: http://groups.google.com/group/funtoo-dev
.. _#funtoo irc channel: irc://irc.freenode.net/funtoo

``Keychain`` helps you to manage ssh and GPG keys in a convenient and secure
manner. It acts as a frontend to ``ssh-agent`` and ``ssh-add``, but allows you
to easily have one long running ``ssh-agent`` process per system, rather than
the norm of one ``ssh-agent`` per login session. 

This dramatically reduces the number of times you need to enter your
passphrase. With ``keychain``, you only need to enter a passphrase once every
time your local machine is rebooted. ``Keychain`` also makes it easy for remote
cron jobs to securely "hook in" to a long running ``ssh-agent`` process,
allowing your scripts to take advantage of key-based logins.

Download and Resources
======================

The latest release of keychain is version ``2.6.9``, and was released on July
26, 2009. The current version of keychain supports ``gpg-agent`` as well as
``ssh-agent``.

Keychain is compatible with many operating systems, including ``AIX``,
``*BSD``, ``Cygwin``, ``MacOS X``, ``Linux``, ``HP/UX``, ``Tru64 UNIX``,
``IRIX``, ``Solaris`` and ``GNU Hurd``. 

.. _keychain 2.6.9 source code: /archive/keychain/keychain-2.6.9.tar.bz2

Download
--------

- `keychain 2.6.9 source code`_

Keychain development sources can be found in the `keychain git repository`_.
Please use the `funtoo-dev mailing list`_ and `#funtoo irc channel`_ for
keychain support questions as well as bug reports.

Background
==========

You're probably familiar with ``ssh``, which has become a secure replacement
for the venerable ``telnet`` and ``rsh`` commands.

Typically, when one uses ``ssh`` to connect to a remote system, one supplies
a secret passphrase to ``ssh``, which is then passed in encrypted form over
the network to the remote server. This passphrase is used by the remote
``sshd`` server to determine if you should be granted access to the system.

However, `OpenSSH` and nearly all other SSH clients and servers have the
ability to perform another type of authentication, called asymmetric public key
authentication, using the RSA or DSA authentication algorithms. They are
very useful, but can also be complicated to use. ``keychain`` has been
designed to make it easy to take advantage of the benefits of RSA and DSA
authentication.

Generating a Key Pair
=====================

To use RSA and DSA authentication, first you use a program called
``ssh-keygen`` to generate a *key pair* -- two small files. One of the files is
the *public key*.  The other small file contains the *private key*.
``ssh-keygen`` will ask you for a passphrase, and this passphrase will be used
to encrypt your private key. You will need to supply this passphrase to use
your private key. If you wanted to generate a DSA key pair, you would do this::

        # ssh-keygen -t dsa
        Generating public/private dsa key pair.

You would then be prompted for a location to store your key pair. If you
do not have one currently stored in ``~/.ssh``, it is fine to accept the
default location::

        Enter file in which to save the key (/root/.ssh/id_dsa): /var/tmp/id_dsa

Then, you are prompted for a passphrase. This passphrase is used to encrypt the
*private key* on disk, so even if it is stolen, it will be difficult for
someone else to use it to successfully authenticate as you with any accounts
that have been configured to recognize your public key. 

Note that conversely, if you **do not** provide a passphrase for your private
key file, then your private key file **will not** be encrypted. This means that
if someone steals your private key file, *they will have the full ability to
authenticate with any remote accounts that are set up with your public key.*

Below, I have supplied a passphrase so that my private key file will be
encrypted on disk::

        Enter passphrase (empty for no passphrase): 
        Enter same passphrase again: 
        Your identification has been saved in /var/tmp/id_dsa.
        Your public key has been saved in /var/tmp/id_dsa.pub.
        The key fingerprint is:
        5c:13:ff:46:7d:b3:bf:0e:37:1e:5e:8c:7b:a3:88:f4 root@devbox-ve
        The key's randomart image is:
        +--[ DSA 1024]----+
        |          .      |
        |           o   . |
        |          o . ..o|
        |       . . . o  +|
        |        S     o. |
        |             . o.|
        |         .   ..++|
        |        . o . =o*|
        |         . E .+*.|
        +-----------------+

Setting up Authentication
=========================

Here's how you use these files to authenticate with a remote server. On the
remote server, you would append the contents of your *public key* to the
``~.ssh/authorized_keys`` file, if such a file exists. If it doesn't exist, you
can simply create a new ``authorized_keys`` file in the remote account's
``~/.ssh`` directory that contains the contents of your local ``id_dsa.pub``
file.

Then, if you weren't going to use ``keychain``, you'd perform the following
steps. On your local client, you would start a program called ``ssh-agent``,
which runs in the background. Then you would use a program called ``ssh-add``
to tell ``ssh-agent`` about your secret private key. Then, if you've set up
your environment properly, the next time you run ``ssh``, it will find
``ssh-agent`` running, grab the private key that you added to ``ssh-agent``
using ``ssh-add``, and use this key to authenticate with the remote server.

Again, the steps in the previous paragraph is what you'd do if ``keychain``
wasn't around to help. If you are using ``keychain``, and I hope you are, you
would simply add the following line to your ``~/.bash_profile``::

        eval `keychain --eval id_dsa`

The next time you log in or source your ``~/.bash_profile``, ``keychain`` will
start, start ``ssh-agent`` for you if it has not yet been started, use
``ssh-add`` to add your ``id_dsa`` private key file to ``ssh-agent``, and set
up your shell environment so that ``ssh`` will be able to find ``ssh-agent``.
If ``ssh-agent`` is already running, ``keychain`` will ensure that all your
private keys have been added to ``ssh-agent`` and then set up your environment
so that ``ssh`` can find the already-running ``ssh-agent``.

Note that when ``keychain`` runs for the first time after your local system has
booted, you will be prompted for a passphrase for your private key file if it
is encrypted.  But here's the nice thing about using ``keychain`` -- even if
you are using an encrypted private key file, you will only need to enter your
passphrase when your system first boots. After that, ``ssh-agent`` is already
running and has your decrypted private key cached in memory.

This means that you can now ``ssh`` to your heart's content, without supplying
a passphrase. You can also execute batch ``cron`` jobs and scripts that need
to use ``ssh`` or ``scp``, and they can take advantage of passwordless RSA/DSA
authentication as well. To do this, you would add the following line to 
the top of a bash script::

        eval `keychain --noask --eval id_dsa` || exit 1

The extra ``--noask`` option tells ``keychain`` that it should not prompt for a
passphrase if one is needed. Since it is not running interactively, it is
better for the script to fail if the decrypted private key isn't cached in
memory via ``ssh-agent``.

Learning More
=============

The instructions above will work on any system that uses ``bash`` as its
default shell, such as most Linux systems and Mac OS X.

To learn more about the many things that ``keychain`` can do, including
alternate shell support, consult the keychain man page, or type ``keychain
--help`` for a full list of command options.

I also recommend you read my original series of articles about `OpenSSH`_ that
I wrote for IBM developerWorks, called ``OpenSSH Key Management``.  Please note
that ``keychain`` 1.0 was released along with Part 2 of this article, which was
written in 2001.  ``keychain`` has changed quite a bit since then.  In other
words, read these articles for the conceptual and `OpenSSH`_ information, but
consult the ``keychain`` man page for command-line options and usage
instructions :)

- `Common Threads: OpenSSH key management, Part 1`_ - Understanding RSA/DSA Authentication
- `Common Threads: OpenSSH key management, Part 2`_ - Introducing ``ssh-agent`` and ``keychain``
- `Common Threads: OpenSSH key management, Part 3`_ - Agent forwarding and ``keychain`` improvements

As mentioned at the top of the page, ``keychain`` development sources can be
found in the `keychain git repository`_.  Please use the `funtoo-dev mailing
list`_ and `#funtoo irc channel`_ for keychain support questions as well as bug
reports.

Project History
===============

Daniel Robbins originally wrote ``keychain`` 1.0 through 2.0.3. 1.0 was written
around June 2001, and 2.0.3 was released in late August, 2002.

After 2.0.3, ``keychain`` was maintained by various Gentoo developers,
including Seth Chandler, Mike Frysinger and Robin H. Johnson, through July 3,
2003.

On April 21, 2004, Aron Griffis committed a major rewrite of ``keychain`` which
was released as 2.2.0. Aron continued to actively maintain and improve
``keychain`` through October 2006 and the ``keychain`` 2.6.8 release. He also
made a few commits after that date, up through mid-July, 2007.

At this point, ``keychain`` had reached a point of maturity. From mid-July 2007
through late July 2009, a period of over two years, there have been no new
releases. However, a few little tweaks and improvements have been circulating
around, so...

.. _bugs.gentoo.org: http://bugs.gentoo.org

In mid-July, 2009, Daniel Robbins migrated Aron's mercurial repository to git
and set up a new project page on funtoo.org, and made a few bug fix commits to
the git repo that had been collecting in `bugs.gentoo.org`_. Daniel continues
to maintain ``keychain`` and supporting documentation on funtoo.org, and
plans to make regular maintenance releases of ``keychain`` as appropriate.

The current release of ``keychain`` is currently 2.6.9.

