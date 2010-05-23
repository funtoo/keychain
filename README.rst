========================
Introduction to Keychain
========================

:keywords: keychain, funtoo, gentoo, Daniel Robbins
:description: 

        This page contains information about Keychain, an OpenSSH and
        commercial SSH2-compatible RSA/DSA key management application.

:version: 2010.05.07
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

The latest release of keychain is version ``2.7.1``, and was released on
May 7, 2010. The current version of keychain supports ``gpg-agent`` as
well as ``ssh-agent``.

Keychain is compatible with many operating systems, including ``AIX``,
``*BSD``, ``Cygwin``, ``MacOS X``, ``Linux``, ``HP/UX``, ``Tru64 UNIX``,
``IRIX``, ``Solaris`` and ``GNU Hurd``. 


.. _keychain 2.7.1: http://www.funtoo.org/archive/keychain/keychain-2.7.1.tar.bz2

.. _keychain 2.7.1 MacOS X package: http://www.funtoo.org/archive/keychain/keychain-2.7.1-macosx.tar.gz

Download
--------

- *Release Archive*

  - `keychain 2.7.1`_

- *Apple MacOS X Packages*

  - `keychain 2.7.0 MacOS X package`_

  - `keychain 2.6.9 MacOS X package`_

Keychain development sources can be found in the `keychain git repository`_.
Please use the `funtoo-dev mailing list`_ and `#funtoo irc channel`_ for
keychain support questions as well as bug reports.

Quick Setup
===========

Linux
-----

To install under Gentoo or Funtoo Linux, type ``emerge keychain``. For other
Linux distributions, use your distribution's package manager. Then generate
RSA/DSA keys if necessary. The quick install docs assume you have a DSA key
pair named ``id_dsa`` and ``id_dsa.pub`` in your ``~/.ssh/`` directory.  Add
the following to your ``~/.bash_profile``::

        eval `keychain --eval --agents ssh id_dsa`

If you want to take advantage of GPG functionality, ensure that GNU Privacy
Guard is installed and omit the ``--agents ssh`` option above.

Apple MacOS X
-------------

To install under MacOS X, install the MacOS X package for keychain. Assuming
you have an ``id_dsa`` and ``id_dsa.pub`` key pair in your ``~/.ssh/``
directory, add the following to your ``~/.bash_profile``::

        eval `keychain --eval --agents ssh --inherit any id_dsa`

The ``--inherit any`` option above causes keychain to inherit any ssh key
passphrases stored in your Apple MacOS Keychain. If you would prefer for this
to not happen, then this option can be omitted.

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
``ssh-keygen`` (included with OpenSSH) to generate a *key pair* -- two small
files. One of the files is the *public key*.  The other small file contains the
*private key*.  ``ssh-keygen`` will ask you for a passphrase, and this
passphrase will be used to encrypt your private key. You will need to supply
this passphrase to use your private key. If you wanted to generate a DSA key
pair, you would do this::

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
If ``ssh-agent`` is already running, ``keychain`` will ensure that your ``id_dsa`` 
private key has been added to ``ssh-agent`` and then set up your environment
so that ``ssh`` can find the already-running ``ssh-agent``. It will look 
something like this:

.. figure:: keychain-1.png
   :alt: Keychain starts for the first time after login

Note that when ``keychain`` runs for the first time after your local system has
booted, you will be prompted for a passphrase for your private key file if it
is encrypted.  But here's the nice thing about using ``keychain`` -- even if
you are using an encrypted private key file, you will only need to enter your
passphrase when your system first boots (or in the case of a server, when you
first log in.) After that, ``ssh-agent`` is already running and has your
decrypted private key cached in memory. So if you open a new shell, you will
see something like this:

.. figure:: keychain-2.png
   :alt: Keychain finds existing ssh-agent and gpg-agent, and doesn't prompt for passphrase

This means that you can now ``ssh`` to your heart's content, without supplying
a passphrase. 

You can also execute batch ``cron`` jobs and scripts that need
to use ``ssh`` or ``scp``, and they can take advantage of passwordless RSA/DSA
authentication as well. To do this, you would add the following line to 
the top of a bash script::

        eval `keychain --noask --eval id_dsa` || exit 1

The extra ``--noask`` option tells ``keychain`` that it should not prompt for a
passphrase if one is needed. Since it is not running interactively, it is
better for the script to fail if the decrypted private key isn't cached in
memory via ``ssh-agent``.

Keychain Options
================

Specifying Agents
-----------------

In the images above, you will note that ``keychain`` starts ``ssh-agent``, but also
starts ``gpg-agent``. Modern versions of ``keychain`` also support caching decrypted
GPG keys via use of ``gpg-agent``, and will start ``gpg-agent`` by default if it
is available on your system. To avoid this behavior and only start ``ssh-agent``,
modify your ``~/.bash_profile`` as follows::

        eval `keychain --agents ssh --eval id_dsa` || exit 1

The additional ``--agents ssh`` option tells ``keychain`` just to manage ``ssh-agent``,
and ignore ``gpg-agent`` even if it is available.

Clearing Keys
-------------

Sometimes, it might be necessary to flush all cached keys in memory. To do
this, type::

        keychain --clear

Any agent(s) will continue to run. 

Improving Security
------------------

To improve the security of ``keychain``, some people add the ``--clear`` option to
their ``~/.bash_profile`` ``keychain`` invocation. The rationale behind this is that
any user logging in should be assumed to be an intruder until proven otherwise. This
means that you will need to re-enter any passphrases when you log in, but cron jobs
will still be able to run when you log out.

Stopping Agents
---------------

If you want to stop all agents, which will also of course cause your
keys/identities to be flushed from memory, you can do this as follows::

        keychain -k all

If you have other agents running under your user account, you can also tell
``keychain`` to just stop only the agents that ``keychain`` started::

        keychain -k mine

Learning More
=============

The instructions above will work on any system that uses ``bash`` as its
default shell, such as most Linux systems and Mac OS X.

To learn more about the many things that ``keychain`` can do, including
alternate shell support, consult the keychain man page, or type ``keychain
--help | less`` for a full list of command options.

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
made a few commits after that date, up through mid-July, 2007.  At this point,
``keychain`` had reached a point of maturity. 

.. _bugs.gentoo.org: http://bugs.gentoo.org

In mid-July, 2009, Daniel Robbins migrated Aron's mercurial repository to git
and set up a new project page on funtoo.org, and made a few bug fix commits to
the git repo that had been collecting in `bugs.gentoo.org`_. Daniel continues
to maintain ``keychain`` and supporting documentation on funtoo.org, and
plans to make regular maintenance releases of ``keychain`` as needed.

