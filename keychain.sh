#!/bin/sh
# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Author: Daniel Robbins <drobbins@gentoo.org>
# Previous Maintainer: Seth Chandler <sethbc@gentoo.org>
# Current Maintainer: Aron Griffis <agriffis@gentoo.org>
# $Header$

version=2.5.0

PATH="/usr/bin:/bin:/sbin:/usr/sbin:/usr/ucb:${PATH}"

maintainer="agriffis@gentoo.org"
zero=`basename "$0"`
unset mesglog
unset myaction
unset agentsopt
havelock=false
unset hostopt
ignoreopt=false
noaskopt=false
noguiopt=false
nolockopt=false
lockwait=30
openssh=unknown
sunssh=unknown
quickopt=false
quietopt=false
clearopt=false
inheritwhich=local-once
unset stopwhich
unset timeout
attempts=1
unset sshavail
unset sshkeys
unset gpgkeys
unset mykeys
keydir="${HOME}/.keychain"

BLUE="[34;01m"
CYAN="[36;01m"
GREEN="[32;01m"
OFF="[0m"
RED="[31;01m"

# synopsis: qprint "message"
qprint() {
    $quietopt || echo "$*" >&2
}

# synopsis: mesg "message"
# Prettily print something to stderr, honors quietopt
mesg() {
    qprint " ${GREEN}*${OFF} $*"
}

# synopsis: warn "message"
# Prettily print a warning to stderr
warn() {
    echo " ${RED}* Warning${OFF}: $*" >&2
}

# synopsis: error "message"
# Prettily print an error
error() {
    echo " ${RED}* Error${OFF}: $*" >&2
}

# synopsis: die "message"
# Prettily print an error, then abort
die() {
    [ -n "$1" ] && error "$*"
    qprint
    exit 1
}

# synopsis: versinfo
# Display the version information
versinfo() {
    qprint
    qprint "${GREEN}KeyChain ${version}; ${BLUE}http://www.gentoo.org/proj/en/keychain/${OFF}"
    qprint "Copyright 2002-2004 Gentoo Foundation; Distributed under the GPL"
    qprint
}

# synopsis: helpinfo
# Display the help information. There's no really good way to use qprint for
# this...
helpinfo() {
    cat >&2 <<EOHELP
INSERT_POD_OUTPUT_HERE
EOHELP
}

# synopsis: testssh
# Figure out which ssh is in use, set the global boolean $openssh and $sunssh
testssh() {
    # Query local host for SSH application, presently supporting 
    # OpenSSH, Sun SSH, and ssh.com
    openssh=false
    sunssh=false
    case "`ssh -V 2>&1`" in
        *OpenSSH*) openssh=true ;;
        *Sun?SSH*) sunssh=true ;;
    esac
}

# synopsis: getuser
# Set the global string $me
getuser() {
    # whoami gives euid, which might be different from USER or LOGNAME
    me=`whoami` || die "Who are you?  whoami doesn't know..."
}

# synopsis: getos
# Set the global string $OSTYPE
getos() {
    OSTYPE=`uname` || die 'uname failed'
}

# synopsis: verifykeydir
# Make sure the key dir is set up correctly.  Exits on error.
verifykeydir() {
    # Create keydir if it doesn't exist already
    if [ -f "${keydir}" ]; then
        die "${keydir} is a file (it should be a directory)"
    # Solaris 9 doesn't have -e; using -d....
    elif [ ! -d "${keydir}" ]; then
        mkdir "${keydir}"      || die "can't create ${keydir}"
        chmod 0700 "${keydir}" || die "can't chmod ${keydir}"
    fi
}

# synopsis: now previous_now
# Returns some seconds value on stdout, for timing things.  Accepts a
# previous_now parameter which should be the last value returned.  (No data can
# be persistent because this is called from a subshell.) If this is called less
# than once per minute on a non-GNU system then it might skip a minute.
now() {
    if [ -n "$BASH_VERSION" -a "$SECONDS" -ge 0 ] 2>/dev/null; then
        echo $SECONDS
        return 0
    fi

    if now_seconds=`date +%s 2>/dev/null` \
            && [ "$now_seconds" -gt 0 ] 2>/dev/null; then
        if [ $now_seconds -lt "$1" ] 2>/dev/null; then
            warn "time went backwards, taking countermeasures"
            echo `expr $1 + 1`
        else
            echo $now_seconds
        fi
        return 0
    fi

    # Don't use awk -F'[: ]' here because Solaris awk can't handle it, a regex
    # field separator needs gawk or nawk.  It's easier to simply avoid awk in
    # this case.
    if now_seconds=`LC_ALL=C date 2>/dev/null | sed 's/:/ /g' | xargs | cut -d' ' -f6` \
            && [ "$now_seconds" -ge 0 ] 2>/dev/null; then
        if [ -n "$1" ]; then
            # how many minutes have passed previously?
            now_mult=`expr $1 / 60`
            if [ "$now_seconds" -lt `expr $1 % 60` ]; then
                # another minute has passed
                now_mult=`expr $now_mult + 1`
            fi
            # accumulate minutes in now_seconds
            now_seconds=`expr 60 \* $now_mult + $now_seconds`
        fi
        echo $now_seconds
        return 0
    fi

    return 1
}

# synopsis: takelock
# Attempts to get the lockfile $lockf.  If locking isn't available, just returns.
# If locking is available but can't get the lock, exits with error.
takelock() {
    # Check if we already have the lock.  Since this is not a threaded prog,
    # using this global is safe
    $havelock && return 0

    # Honor --nolock
    if $nolockopt; then
        unset lockf
        return 0
    fi

    tl_faking=false
    unset tl_oldpid

    # Setup timer
    if [ $lockwait -eq 0 ]; then
        true    # don't bother to set tl_start, tl_end, tl_current
    elif tl_start=`now`; then
        tl_end=`expr $tl_start + $lockwait`
        tl_current=$tl_start
    else
        # we'll fake it the best we can
        tl_faking=true
        tl_start=0
        tl_end=`expr $lockwait \* 10`
        tl_current=0
    fi

    # Try to lock for $lockwait seconds
    while [ $lockwait -eq 0 -o $tl_current -lt $tl_end ]; do
        if tl_error=`ln -s $$ "$lockf" 2>&1`; then
            havelock=true
            return 0
        fi

        # advance our timer
        if [ $lockwait -gt 0 ]; then
            if $tl_faking; then
                tl_current=`expr $tl_current + 1`
            else
                tl_current=`now $tl_current`
            fi
        fi

        # check for old-style lock; unlikely
        if [ -f "$lockf" ]; then
            error "please remove old-style lock: $lockf"
            return 1
        fi

        # read the lock
        tl_pid=`readlink "$lockf" 2>/dev/null`
        if [ -z "$tl_pid" ]; then 
            tl_pid=`ls -l "$lockf" 2>/dev/null | awk '{print $NF}'`
        fi
        if [ -z "$tl_pid" ]; then
            # lock seems to have disappeared, try again
            continue
        fi

        # test for a stale lock
        kill -0 "$tl_pid" 2>/dev/null
        if [ $? != 0 ]; then
            # Avoid a race condition; another keychain might have started at
            # this point.  If the pid is the same as the last time we
            # checked, then go ahead and remove the stale lock.  Otherwise
            # remember the pid and try again.
            if [ "$tl_pid" = "$tl_oldpid" ]; then
                warn "removing stale lock for pid $tl_pid"
                rm -f "$lockf"
            else
                tl_oldpid="$tl_pid"
            fi
            # try try again
            continue
        fi

        # sleep for a bit to wait for the keychain process holding the lock
        sleep 0.1 >/dev/null 2>&1 && continue
        perl -e 'select(undef, undef, undef, 0.1)' \
            >/dev/null 2>&1 && continue
        # adjust granularity of tl_current stepping
        $tl_faking && tl_current=`expr $tl_current + 9`
        sleep 1
    done

    # no luck
    [ -n "$tl_pid" ] || unset tl_pid    # ${var+...} relies on set vs. unset
    error "failed to get the lock${tl_pid+, held by pid $tl_pid}: $tl_error"
    return 1
}

# synopsis: droplock
# Drops the lock if we're holding it.
droplock() {
    [ -n "$lockf" ] && rm -f "$lockf"
}

# synopsis: findpids [prog]
# Returns a space-separated list of agent pids.
# prog can be ssh or gpg, defaults to ssh.  Note that if another prog is ever
# added, need to pay attention to the length for Solaris compatibility.
findpids() {
    fp_prog=${1-ssh}
    unset fp_psout

    # Different systems require different invocations of ps.  Try to generalize
    # the best we can.  The only requirement is that the agent command name
    # appears in the line, and the PID is the first item on the line.
    [ -n "$OSTYPE" ] || getos

    # Try systems where we know what to do first
    case "$OSTYPE" in
        AIX|*bsd*|*BSD*|CYGWIN|darwin*|Linux|OSF1)
            fp_psout=`ps x 2>/dev/null` ;;      # BSD syntax
        HP-UX)
            fp_psout=`ps -u $me 2>/dev/null` ;; # SysV syntax
        SunOS)
            case `uname -r` in
                [56]*)
                    fp_psout=`ps -u $me 2>/dev/null` ;; # SysV syntax
                *)
                    fp_psout=`ps x 2>/dev/null` ;;      # BSD syntax
            esac ;;
    esac

    # If we didn't get a match above, try a list of possibilities...
    # The first one will probably fail on systems supporting only BSD syntax.
    if [ -z "$fp_psout" ]; then
        fp_psout=`UNIX95=1 ps -u $me -o pid,comm 2>/dev/null | grep '^ *[0-9]'`
        [ -z "$fp_psout" ] && fp_psout=`ps x 2>/dev/null`
    fi

    # Return the list of pids; ignore case for Cygwin.
    # Check only 8 characters since Solaris truncates at that length.
    # Ignore defunct ssh-agents (bug 28599)
    if [ -n "$fp_psout" ]; then
        echo "$fp_psout" | \
            awk "BEGIN{IGNORECASE=1} /defunct/{next}
                /$fp_prog-[a]gen/{print \$1}" | xargs
        return 0
    fi

    # If none worked, we're stuck
    error "Unable to use \"ps\" to scan for $fp_prog-agent processes"
    error "Please report to $maintainer via http://bugs.gentoo.org"
    return 1
}

# synopsis: stopagent [prog]
# --stop tells keychain to kill the existing agent(s)
# prog can be ssh or gpg, defaults to ssh.
stopagent() {
    stop_prog=${1-ssh}
    eval stop_except=\$\{${stop_prog}_agent_pid\}
    stop_mypids=`findpids "$stop_prog"`
    [ $? = 0 ] || die

    if [ -z "$stop_mypids" ]; then
        mesg "No $stop_prog-agent(s) found running"
        return 0
    fi

    case "$stopwhich" in
        all)
            kill $stop_mypids >/dev/null 2>&1
            mesg "All $me's $stop_prog-agent(s) ($stop_mypids) are now stopped"
            ;;

        others)
            # Try to handle the case where we *will* inherit a pid
            if [ -z "$stop_except" ] || ! kill -0 $stop_except >/dev/null 2>&1 || \
                    [ "$inheritwhich" = local -o "$inheritwhich" = any ]; then
                if [ "$inheritwhich" != none ]; then
                    eval stop_except=\$\{inherit_${stop_prog}_agent_pid\}
                    if [ -z "$stop_except" ] || ! kill -0 $stop_except >/dev/null 2>&1; then
                        # Handle ssh2
                        eval stop_except=\$\{inherit_${stop_prog}2_agent_pid\}
                    fi
                fi
            fi

            # Filter out the running agent pid
            unset stop_mynewpids
            for stop_x in $stop_mypids; do
                [ $stop_x -eq $stop_except ] 2>/dev/null && continue
                stop_mynewpids="${stop_mynewpids+$stop_mynewpids }$stop_x"
            done

            if [ -n "$stop_mynewpids" ]; then
                kill $stop_mynewpids >/dev/null 2>&1
                mesg "Other $me's $stop_prog-agent(s) ($stop_mynewpids) are now stopped"
            else
                mesg "No other $stop_prog-agent(s) than keychain's $stop_except found running"
            fi
            ;;

        mine)
            if [ $stop_except -gt 0 ] 2>/dev/null; then
                kill $stop_except >/dev/null 2>&1
                mesg "Keychain $stop_prog-agent $stop_except is now stopped"
            else
                mesg "No keychain $stop_prog-agent found running"
            fi
            ;;
    esac

    # remove pid files if keychain-controlled 
    if [ "$stopwhich" != others ]; then
        if [ "$stop_prog" != ssh ]; then
            rm -f "${pidf}-$stop_prog" "${cshpidf}-$stop_prog" 2>/dev/null
        else
            rm -f "${pidf}" "${cshpidf}" 2>/dev/null
        fi

        eval unset ${stop_prog}_agent_pid
    fi
}

# synopsis: inheritagents
# Save agent variables from the environment before they get wiped out
inheritagents() {
    # Verify these global vars are null
    unset inherit_ssh_auth_sock inherit_ssh_agent_pid 
    unset inherit_ssh2_auth_sock inherit_ssh2_agent_sock
    unset inherit_gpg_agent_info inherit_gpg_agent_pid

    # Save variables so we can inherit a running agent
    if [ "$inheritwhich" != none ]; then
        if wantagent ssh; then
            if [ -n "$SSH_AUTH_SOCK" ]; then
                if ls "$SSH_AUTH_SOCK" >/dev/null 2>&1; then
                    inherit_ssh_auth_sock="$SSH_AUTH_SOCK"
                    inherit_ssh_agent_pid="$SSH_AGENT_PID"
                else
                    warn "SSH_AUTH_SOCK in environment is invalid; ignoring it"
                fi
            fi

            if [ -z "$inherit_ssh_auth_sock" -a -n "$SSH2_AUTH_SOCK" ]; then 
                if ls "$SSH2_AUTH_SOCK" >/dev/null 2>&1; then
                    inherit_ssh2_auth_sock="$SSH2_AUTH_SOCK"
                    inherit_ssh2_agent_pid="$SSH2_AGENT_PID"
                else
                    warn "SSH2_AUTH_SOCK in environment is invalid; ignoring it"
                fi
            fi
        fi

        if wantagent gpg; then
            if [ -n "$GPG_AGENT_INFO" ]; then
                la_IFS="$IFS"  # save current IFS
                IFS=':'        # set IFS to colon to separate PATH
                set -- $GPG_AGENT_INFO
                IFS="$la_IFS"  # restore IFS
                if kill -0 "$2" >/dev/null 2>&1; then
                    inherit_gpg_agent_pid="$2"
                    inherit_gpg_agent_info="$GPG_AGENT_INFO"
                else
                    warn "GPG_AGENT_INFO in environment is invalid; ignoring it"
                fi
            fi
        fi
    fi
}

# synopsis: loadagents
# Load agent variables from $pidf and copy implementation-specific environment
# variables into generic global strings
loadagents() {
    unset SSH_AUTH_SOCK SSH_AGENT_PID SSH2_AUTH_SOCK SSH2_AGENT_PID
    unset GPG_AGENT_INFO    # too bad we have to do this explicitly

    # Load agent pid files
    for ql_x in "$pidf" "$pidf"-*; do
        [ -f "$ql_x" ] && . "$ql_x"
    done

    # Copy implementation-specific environment variables into generic local
    # variables.
    if [ -n "$SSH_AUTH_SOCK" ]; then
        ssh_auth_sock=$SSH_AUTH_SOCK
        ssh_agent_pid=$SSH_AGENT_PID
    elif [ -n "$SSH2_AUTH_SOCK" ]; then
        ssh_auth_sock=$SSH2_AUTH_SOCK
        ssh_agent_pid=$SSH2_AGENT_PID
    else
        unset ssh_auth_sock ssh_agent_pid
    fi

    if [ -n "$GPG_AGENT_INFO" ]; then
        la_IFS="$IFS"  # save current IFS
        IFS=':'        # set IFS to colon to separate PATH
        set -- $GPG_AGENT_INFO
        IFS="$la_IFS"  # restore IFS
        gpg_agent_pid=$2
    fi

    return 0
}

# synopsis: startagent [prog]
# Starts an agent if it isn't already running.
# Requires $ssh_agent_pid
startagent() {
    start_prog=${1-ssh}
    unset start_pid
    start_inherit_pid=none
    start_mypids=`findpids "$start_prog"`
    [ $? = 0 ] || die

    # Unfortunately there isn't much way to genericize this without introducing
    # a lot more supporting code/structures.
    if [ "$start_prog" = ssh ]; then
        start_pidf="$pidf"
        start_cshpidf="$cshpidf"
        start_pid="$ssh_agent_pid"
        if [ -n "$inherit_ssh_auth_sock" -o -n "$inherit_ssh2_auth_sock" ]; then
            if [ -n "$inherit_ssh_agent_pid" ]; then
                start_inherit_pid="$inherit_ssh_agent_pid"
            elif [ -n "$inherit_ssh2_agent_pid" ]; then
                start_inherit_pid="$inherit_ssh2_agent_pid"
            else
                start_inherit_pid="forwarded"
            fi
        fi
    else
        start_pidf="${pidf}-$start_prog"
        start_cshpidf="${cshpidf}-$start_prog"
        if [ "$start_prog" = gpg ]; then
            start_pid="$gpg_agent_pid"
            if [ -n "$inherit_gpg_agent_pid" ]; then
                start_inherit_pid="$inherit_gpg_agent_pid"
            fi
        else
            error "I don't know how to start $start_prog-agent (1)"
            return 1
        fi
    fi
    [ "$start_pid" -gt 0 ] 2>/dev/null || start_pid=none

    # This hack makes the case statement easier
    if [ "$inheritwhich" = any -o "$inheritwhich" = any-once ]; then
        start_fwdflg=forwarded
    else
        unset start_fwdflg
    fi

    # Check for an existing agent
    case "$inheritwhich: $start_mypids $start_fwdflg " in
        any:*" $start_inherit_pid "*|local:*" $start_inherit_pid "*)
            mesg "Inheriting ${start_prog}-agent ($start_inherit_pid)"
            ;;

        none:*" $start_pid "*|*-once:*" $start_pid "*)
            mesg "Found existing ${start_prog}-agent ($start_pid)"
            return 0
            ;;

        *-once:*" $start_inherit_pid "*)
            mesg "Inheriting ${start_prog}-agent ($start_inherit_pid)"
            ;;
    esac

    # Init the bourne-formatted pidfile
    mesg "Initializing $start_pidf file..."
    :> "$start_pidf" && chmod 0600 "$start_pidf"
    if [ $? != 0 ]; then
        rm -f "$start_pidf" "$start_cshpidf" 2>/dev/null
        error "can't create $start_pidf"
        return 1
    fi

    # Init the csh-formatted pidfile
    mesg "Initializing $start_cshpidf file..."
    :> "$start_cshpidf" && chmod 0600 "$start_cshpidf"
    if [ $? != 0 ]; then
        rm -f "$start_pidf" "$start_cshpidf" 2>/dev/null
        error "can't create $start_cshpidf"
        return 1
    fi

    # Determine content for files
    unset start_out
    if [ "$start_inherit_pid" = none ]; then

        # Start the agent.
        # Branch again since the agents start differently
        mesg "Starting ${start_prog}-agent"
        if [ "$start_prog" = ssh ]; then
            start_out=`ssh-agent`
        elif [ "$start_prog" = gpg ]; then
            if [ -n "${timeout}" ]; then
                start_gpg_timeout="--default-cache-ttl `expr $timeout \* 60`"
            else
                unset start_gpg_timeout
            fi
            # the 1.9.x series of gpg spews debug on stderr
            start_out=`gpg-agent --daemon $start_gpg_timeout 2>/dev/null`
        else
            error "I don't know how to start $start_prog-agent (2)"
            return 1
        fi
        if [ $? != 0 ]; then
            rm -f "$start_pidf" "$start_cshpidf" 2>/dev/null
            error "Failed to start ${start_prog}-agent"
            return 1
        fi

    elif [ "$start_prog" = ssh -a -n "$inherit_ssh_auth_sock" ]; then
        start_out="SSH_AUTH_SOCK=$inherit_ssh_auth_sock; export SSH_AUTH_SOCK;"
        if [ "$inherit_ssh_agent_pid" -gt 0 ] 2>/dev/null; then
            start_out="$start_out
SSH_AGENT_PID=$inherit_ssh_agent_pid; export SSH_AGENT_PID;"
        fi
    elif [ "$start_prog" = ssh -a -n "$inherit_ssh2_auth_sock" ]; then
        start_out="SSH2_AUTH_SOCK=$inherit_ssh2_auth_sock; export SSH2_AUTH_SOCK;
SSH2_AGENT_PID=$inherit_ssh2_agent_pid; export SSH2_AGENT_PID;"
        if [ "$inherit_ssh2_agent_pid" -gt 0 ] 2>/dev/null; then
            start_out="$start_out
SSH2_AGENT_PID=$inherit_ssh2_agent_pid; export SSH2_AGENT_PID;"
        fi
    
    elif [ "$start_prog" = gpg -a -n "$inherit_gpg_agent_info" ]; then
        start_out="GPG_AGENT_INFO=$inherit_gpg_agent_info; export GPG_AGENT_INFO;"

    else
        die "something bad happened"    # should never be here
    fi

    # Add content to pidfiles.
    # Some versions of ssh-agent don't understand -s, which means to
    # generate Bourne shell syntax.  It appears they also ignore SHELL,
    # according to http://bugs.gentoo.org/show_bug.cgi?id=52874
    # So make no assumptions.
    start_out=`echo "$start_out" | grep -v 'Agent pid'`
    case "$start_out" in
        setenv*)
            echo "$start_out" >"$start_cshpidf"
            echo "$start_out" | awk '{print $2"="$3" export "$2";"}' >"$start_pidf"
            ;;
        *)
            echo "$start_out" >"$start_pidf"
            echo "$start_out" | sed 's/;.*/;/' | sed 's/=/ /' | sed 's/^/setenv /' >"$start_cshpidf"
            ;;
    esac

    # Hey the agent should be started now... load it up!
    loadagents
}

# synopsis: ssh_l
# Return space-separated list of known fingerprints
ssh_l() {
    sl_mylist=`ssh-add -l 2>/dev/null`
    sl_retval=$?

    if $openssh; then
        # Error codes:
        #   0  success
        #   1  OpenSSH_3.8.1p1 on Linux: no identities (not an error)
        #      OpenSSH_3.0.2p1 on HP-UX: can't connect to auth agent
        #   2  can't connect to auth agent
        case $sl_retval in
            0)
                # Output of ssh-add -l:
                #   1024 7c:c3:e2:7e:fb:05:43:f1:8e:e6:91:0d:02:a0:f0:9f .ssh/id_dsa (DSA)
                # Return a space-separated list of fingerprints
                echo "$sl_mylist" | cut -f2 -d' ' | xargs
                return 0
                ;;
            1)
                case "$sl_mylist" in
                    *"open a connection"*) sl_retval=2 ;;
                esac
                ;;
        esac
        return $sl_retval

    elif $sunssh; then
        # Error codes (from http://docs.sun.com/db/doc/817-3936/6mjgdbvio?a=view)
        #   0  success (even when there are no keys)
        #   1  error
        case $sl_retval in
            0)
                # Output of ssh-add -l:
                #   md5 1024 7c:c3:e2:7e:fb:05:43:f1:8e:e6:91:0d:02:a0:f0:9f /home/harvey/.ssh/id_dsa(DSA)
                # Return a space-separated list of fingerprints
                echo "$sl_mylist" | cut -f3 -d' ' | xargs
                return 0
                ;;
            1)
                case "$sl_mylist" in
                    *"open a connection"*) sl_retval=2 ;;
                esac
                ;;
        esac
        return $sl_retval

    else
        # Error codes:
        #   0  success - however might say "The authorization agent has no keys."
        #   1  can't connect to auth agent
        #   2  bad passphrase
        #   3  bad identity file
        #   4  the agent does not have the requested identity
        #   5  unspecified error
        if [ $sl_retval = 0 ]; then
            # Output of ssh-add -l:
            #   The authorization agent has one key:
            #   id_dsa_2048_a: 2048-bit dsa, agriffis@alpha.zk3.dec.com, Fri Jul 25 2003 10:53:49 -0400
            # Since we don't have a fingerprint, just get the filenames *shrug*
            echo "$sl_mylist" | sed '2,$s/:.*//' | xargs
        fi
        return $sl_retval
    fi
}

# synopsis: ssh_f filename
# Return finger print for a keyfile
# Requires $openssh and $sunssh
ssh_f() {
    sf_filename="$1"
    if $openssh || $sunssh; then
        if [ ! -f "$sf_filename.pub" ]; then
            warn "$sf_filename.pub missing; can't tell if $sf_filename is loaded"
            return 1
        fi
        sf_fing=`ssh-keygen -l -f "$sf_filename.pub"` || return 1
        if $sunssh; then
            # md5 1024 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00 /home/barney/.ssh/id_dsa(DSA)
            echo "$sf_fing" | cut -f3 -d' '
        else
            # 1024 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00 /home/barney/.ssh/id_dsa (DSA)
            echo "$sf_fing" | cut -f2 -d' '
        fi
    else
        # can't get fingerprint for ssh2 so use filename *shrug*
        basename "$sf_filename"
    fi
    return 0
}

# synopsis: gpg_listmissing
# Uses $gpgkeys
# Returns a newline-separated list of keys found to be missing.
gpg_listmissing() {
    unset glm_missing

    glm_disp="$DISPLAY"
    unset DISPLAY

    # Parse $gpgkeys into positional params to preserve spaces in filenames
    set -f;        # disable globbing
    glm_IFS="$IFS"  # save current IFS
    IFS="
"                  # set IFS to newline
    set -- $gpgkeys
    IFS="$glm_IFS"  # restore IFS
    set +f         # re-enable globbing

    for glm_k in "$@"; do
        # Check if this key is known to the agent.  Don't know another way...
        if echo | gpg --no-tty --sign --local-user "$glm_k" -o - >/dev/null 2>&1; then
            # already know about this key
            mesg "Known gpg key: ${BLUE}${glm_k}${OFF}"
            continue
        else
            # need to add this key
            if [ -z "$glm_missing" ]; then
                glm_missing="$glm_k"
            else
                glm_missing="$glm_missing
$glm_k"
            fi
        fi
    done

    DISPLAY="$glm_disp"

    echo "$glm_missing"
}

# synopsis: ssh_listmissing
# Uses $sshkeys and $sshavail
# Returns a newline-separated list of keys found to be missing.
ssh_listmissing() {
    unset slm_missing

    # Parse $sshkeys into positional params to preserve spaces in filenames
    set -f;        # disable globbing
    slm_IFS="$IFS"  # save current IFS
    IFS="
"                  # set IFS to newline
    set -- $sshkeys
    IFS="$slm_IFS"  # restore IFS
    set +f         # re-enable globbing

    for slm_k in "$@"; do
        # Fingerprint current user-specified key
        slm_finger=`ssh_f "$slm_k"` || continue

        # Check if it needs to be added
        case " $sshavail " in
            *" $slm_finger "*)
                # already know about this key
                mesg "Known ssh key: ${BLUE}${slm_k}${OFF}"
                ;;
            *)
                # need to add this key
                if [ -z "$slm_missing" ]; then
                    slm_missing="$slm_k"
                else
                    slm_missing="$slm_missing
$slm_k"
                fi
                ;;
        esac
    done

    echo "$slm_missing"
}

# synopsis: add_gpgkey
# Adds a key to $gpgkeys
add_gpgkey() {
    gpgkeys=${gpgkeys+"$gpgkeys
"}"$1"
}

# synopsis: add_sshkey
# Adds a key to $sshkeys
add_sshkey() {
    sshkeys=${sshkeys+"$sshkeys
"}"$1"
}

# synopsis: parse_mykeys
# Sets $sshkeys and $gpgkeys based on $mykeys
parse_mykeys() {
    # Parse $mykeys into positional params to preserve spaces in filenames
    set -f;        # disable globbing
    pm_IFS="$IFS"  # save current IFS
    IFS="
"                  # set IFS to newline
    set -- $mykeys
    IFS="$pm_IFS"  # restore IFS
    set +f         # re-enable globbing

    for pm_k in "$@"; do
        # Check for ssh
        if wantagent ssh; then
            if [ -f "$pm_k" ]; then
                add_sshkey "$pm_k" ; continue
            elif [ -f "$HOME/.ssh/$pm_k" ]; then
                add_sshkey "$HOME/.ssh/$pm_k" ; continue
            elif [ -f "$HOME/.ssh2/$pm_k" ]; then
                add_sshkey "$HOME/.ssh2/$pm_k" ; continue
            fi
        fi

        # Check for gpg
        if wantagent gpg; then
            if [ -z "$pm_gpgsecrets" ]; then
                pm_gpgsecrets="`gpg --list-secret-keys 2>/dev/null | cut -d/ -f2 | cut -d' ' -f1 | xargs`"
                [ -z "$pm_gpgsecrets" ] && pm_gpgsecrets='/'    # arbitrary
            fi
            case " $pm_gpgsecrets " in *" $pm_k "*)
                add_gpgkey "$pm_k" ; continue ;;
            esac
        fi

        $ignoreopt || warn "can't find $pm_k; skipping"
        continue
    done
    
    return 0
}

# synopsis: setaction
# Sets $myaction or dies if $myaction is already set
setaction() {
    if [ -n "$myaction" ]; then
        die "you can't specify --$myaction and $1 at the same time"
    else
        myaction="$1"
    fi
}

# synopsis: in_path
# Look for executables in the path
in_path() {
    ip_lookfor="$1"

    # Parse $PATH into positional params to preserve spaces
    ip_IFS="$IFS"  # save current IFS
    IFS=':'        # set IFS to colon to separate PATH
    set -- $PATH
    IFS="$ip_IFS"  # restore IFS

    for ip_x in "$@"; do
        [ -x "$ip_x/$ip_lookfor" ] || continue
        echo "$ip_x/$ip_lookfor" 
        return 0
    done

    return 1
}

# synopsis: setagents
# Check validity of agentsopt
setagents() {
    if [ -n "$agentsopt" ]; then
        agentsopt=`echo "$agentsopt" | sed 's/,/ /g'`
        unset new_agentsopt
        for a in $agentsopt; do
            if in_path ${a}-agent >/dev/null; then
                new_agentsopt="${new_agentsopt+$new_agentsopt }${a}"
            else
                warn "can't find ${a}-agent, removing from list"
            fi
        done
        agentsopt="${new_agentsopt}"
    else
        for a in ssh gpg; do
            in_path ${a}-agent >/dev/null || continue
            agentsopt="${agentsopt+$agentsopt }${a}"
        done
    fi

    if [ -z "$agentsopt" ]; then
        die "no agents available to start"
    fi
}

# synopsis: wantagent prog
# Return 0 (true) or 1 (false) depending on whether prog is one of the agents in
# agentsopt
wantagent() {
    case "$agentsopt" in
        "$1"|"$1 "*|*" $1 "*|*" $1")
            return 0 ;;
        *)
            return 1 ;;
    esac
}

#
# MAIN PROGRAM
#

# parse the command-line
while [ -n "$1" ]; do
    case "$1" in
        --help|-h) 
            setaction help 
            ;;
        --stop|-k) 
            # As of version 2.5, --stop takes an argument.  For the sake of
            # backward compatibility, only eat the arg if it's one we recognize.
            if [ "$2" = mine ]; then
                stopwhich=mine; shift
            elif [ "$2" = others ]; then
                stopwhich=others; shift
            elif [ "$2" = all ]; then
                stopwhich=all; shift
            else
                # backward compat
                warn "--stop without an argument is deprecated; see --help"
                stopwhich=all
            fi
            ;;
        --version|-V) 
            setaction version 
            ;;
        --agents)
            shift
            agentsopt="$1"
            ;;
        --attempts)
            shift
            if [ "$1" -gt 0 ] 2>/dev/null; then
                attempts=$1
            else
                die "--attempts requires a numeric argument greater than zero"
            fi
            ;;
        --dir)
            shift
            case "$1" in
                */.*) keydir="$1" ;;
                '')   die "--dir requires an argument" ;;
                *)    keydir="$1/.keychain" ;;  # be backward-compatible
            esac
            ;;
        --clear)
            clearopt=true
            $quickopt && die "--quick and --clear are not compatible"
            ;;
        --host)
            shift
            hostopt="$1"
            ;;
        --ignore-missing)
            ignoreopt=true
            ;;
        --inherit)
            shift
            case "$1" in
                local|any|local-once|any-once)
                    inheritwhich="$1"
                    ;;
                *)
                    die "--inherit requires an argument (local, any, local-once or any-once)"
                    ;;
            esac
            ;;
        --noinherit)
            inheritwhich=none
            ;;
        --noask)
            noaskopt=true
            ;;
        --nogui)
            noguiopt=true
            ;;
        --nolock)
            nolockopt=true
            ;;
        --lockwait)
            shift
            if [ "$1" -ge 0 ] 2>/dev/null; then
                lockwait="$1"
            else
                die "--lockwait requires an argument 0 <= n <= 50"
            fi
            ;;
        --quick|-Q)
            quickopt=true
            $clearopt && die "--quick and --clear are not compatible"
            ;;
        --quiet|-q)
            quietopt=true
            ;;
        --nocolor)
            unset BLUE CYAN GREEN OFF RED
            ;;
        --timeout)
            shift
            if [ "$1" -gt 0 ] 2>/dev/null; then
                timeout=$1
            else
                die "--timeout requires a numeric argument greater than zero"
            fi
            ;;
        --)
            shift
            IFS="
"
            mykeys=${mykeys+"$mykeys
"}"$*"
            unset IFS
            break
            ;;
        -*)
            echo "$zero: unknown option $1" >&2
            exit 1
            ;;
        *)
            mykeys=${mykeys+"$mykeys
"}"$1"
            ;;
    esac
    shift
done

# Set filenames *after* parsing command-line options to allow 
# modification of $keydir and/or $hostopt
#
# pidf holds the specific name of the keychain .ssh-agent-myhostname file.
# We use the new hostname extension for NFS compatibility. cshpidf is the
# .ssh-agent file with csh-compatible syntax. lockf is the lockfile, used
# to serialize the execution of multiple ssh-agent processes started 
# simultaneously
[ -z "$hostopt" ] && hostopt=`uname -n 2>/dev/null || echo unknown`
pidf="${keydir}/${hostopt}-sh"
cshpidf="${keydir}/${hostopt}-csh"
lockf="${keydir}/${hostopt}-lock"

# Don't use color if there's no terminal on stdout
if [ -n "$OFF" ]; then
    tty <&1 >/dev/null 2>&1 || unset BLUE CYAN GREEN OFF RED
fi

# versinfo uses qprint, which honors --quiet
versinfo
[ "$myaction" = version ] && exit 0
[ "$myaction" = help ] && { helpinfo; exit 0; }

# Disallow ^C until we've had a chance to --clear.
# Don't use signal names because they don't work on Cygwin.
trap '' 2
trap 'droplock' 0 1 15          # drop the lock on exit

setagents                       # verify/set $agentsopt
verifykeydir                    # sets up $keydir
wantagent ssh && testssh        # sets $openssh and $sunssh
getuser                         # sets $me

# Inherit agent info from the environment before loadagents wipes it out.
# Always call this since it checks $inheritopt and sets variables accordingly.
inheritagents

# --stop: kill the existing ssh-agent(s) and quit
if [ -n "$stopwhich" ]; then 
    takelock || die
    if [ "$stopwhich" = mine -o "$stopwhich" = others ]; then
        loadagents
    fi
    for a in $agentsopt; do
        stopagent $a
    done
    if [ "$stopwhich" != others ]; then
        qprint
        exit 0                  # stopagent is always successful
    fi
fi

# Note regarding locking: if we're trying to be quick, then don't take the lock.
# It will be taken later if we discover we can't be quick.
if $quickopt; then
    loadagents         # sets ssh_auth_sock, ssh_agent_pid, etc
    unset nagentsopt
    for a in $agentsopt; do
        needstart=true

        # Trying to be quick has a price... If we discover the agent isn't running,
        # then we'll have to check things again (in startagent) after taking the
        # lock.  So don't do the initial check unless --quick was specified.
        if [ $a = ssh ]; then
            sshavail=`ssh_l`    # try to use existing agent
                                # 0 = found keys, 1 = no keys, 2 = no agent
            if [ $? = 0 -o \( $? = 1 -a -z "$mykeys" \) ]; then
                mesg "Found existing ssh-agent ($ssh_agent_pid)"
                needstart=false
            fi
        elif [ $a = gpg ]; then
            # not much way to be quick on this
            if [ -n "$gpg_agent_pid" ]; then
                case " `findpids gpg` " in
                    *" $gpg_agent_pid "*) 
                        mesg "Found existing gpg-agent ($gpg_agent_pid)"
                        needstart=false ;;
                esac
            fi
        fi

        $needstart && nagentsopt="$nagentsopt $a"
    done
    agentsopt="$nagentsopt"
fi

# If there are no agents remaining, then bow out now...
[ -n "$agentsopt" ] || { qprint; exit 0; }

# There are agents remaining to start, and we now know we can't be quick.  Take
# the lock before continuing
takelock || die
loadagents
unset nagentsopt
for a in $agentsopt; do
    startagent $a && nagentsopt="${nagentsopt+$nagentsopt }$a"
done
agentsopt="$nagentsopt"

# If there are no agents remaining, then duck out now...
[ -n "$agentsopt" ] || { qprint; exit 0; }

# --timeout translates almost directly to ssh-add -t, but ssh.com uses
# minutes and OpenSSH uses seconds
if [ -n "$timeout" ] && wantagent ssh; then
    ssh_timeout=$timeout
    if $openssh || $sunssh; then
        ssh_timeout=`expr $ssh_timeout \* 60`
    fi
    ssh_timeout="-t $ssh_timeout"
fi

# --clear: remove all keys from the agent(s)
if $clearopt; then
    for a in ${agentsopt}; do
        if [ $a = ssh ]; then
            sshout=`ssh-add -D 2>&1`
            if [ $? = 0 ]; then
                mesg "ssh-agent: $sshout"
            else
                warn "ssh-agent: $sshout"
            fi
        elif [ $a = gpg ]; then
            kill -1 $gpg_agent_pid 2>/dev/null
            mesg "gpg-agent: All identities removed."
        else
            warn "--clear not supported for ${a}-agent"
        fi
    done
fi
trap 'droplock' 2               # done clearing, safe to ctrl-c

# --noask: "don't ask for keys", so we're all done
$noaskopt && { qprint; exit 0; }

# Parse $mykeys into ssh vs. gpg keys; it may be necessary in the future to
# differentiate on the cmdline
parse_mykeys || die

# Load ssh keys
if wantagent ssh; then
    sshavail=`ssh_l`                # update sshavail now that we're locked
    sshkeys="`ssh_listmissing`"     # cache list of missing keys, newline-separated
    sshattempts=$attempts

    # Attempt to add the keys
    while [ -n "$sshkeys" ]; do

        mesg "Adding ${BLUE}"`echo "$sshkeys" | wc -l`"${OFF} ssh key(s)..."

        # Parse $sshkeys into positional params to preserve spaces in filenames.
        # This *must* happen after any calls to subroutines because pure Bourne
        # shell doesn't restore "$@" following a call.  Eeeeek!
        set -f;            # disable globbing
        old_IFS="$IFS"     # save current IFS
        IFS="
"                          # set IFS to newline
        set -- $sshkeys
        IFS="$old_IFS"     # restore IFS
        set +f             # re-enable globbing

        if $noguiopt || [ -z "$SSH_ASKPASS" -o -z "$DISPLAY" ]; then
            unset SSH_ASKPASS   # make sure ssh-add doesn't try SSH_ASKPASS
            sshout=`ssh-add ${ssh_timeout} "$@"`
        else
            sshout=`ssh-add ${ssh_timeout} "$@" </dev/null`
        fi
        [ $? = 0 ] && break

        if [ $sshattempts = 1 ]; then
            die "Problem adding; giving up"
        else
            warn "Problem adding; trying again"
        fi

        # Update the list of missing keys
        sshavail=`ssh_l`
        [ $? = 0 ] || die "problem running ssh-add -l"
        sshkeys="`ssh_listmissing`"  # remember, newline-separated

        # Decrement the countdown
        sshattempts=`expr $sshattempts - 1`
    done
fi

# Load gpg keys
if wantagent gpg; then
    gpgkeys="`gpg_listmissing`"     # cache list of missing keys, newline-separated
    gpgattempts=$attempts

    $noguiopt && unset DISPLAY
    GPG_TTY=`tty` ; export GPG_TTY  # fall back to ncurses pinentry

    # Attempt to add the keys
    while [ -n "$gpgkeys" ]; do
        tryagain=false

        mesg "Adding ${BLUE}"`echo "$gpgkeys" | wc -l`"${OFF} gpg key(s)..."

        # Parse $gpgkeys into positional params to preserve spaces in filenames.
        # This *must* happen after any calls to subroutines because pure Bourne
        # shell doesn't restore "$@" following a call.  Eeeeek!
        set -f;            # disable globbing
        old_IFS="$IFS"     # save current IFS
        IFS="
"                          # set IFS to newline
        set -- $gpgkeys
        IFS="$old_IFS"     # restore IFS
        set +f             # re-enable globbing

        for k in "$@"; do
            echo | gpg --no-tty --sign --local-user "$k" -o - >/dev/null 2>&1
            [ $? != 0 ] && tryagain=true
        done
        $tryagain || break

        if [ $gpgattempts = 1 ]; then
            die "Problem adding; giving up"
        else
            warn "Problem adding; trying again"
        fi

        # Update the list of missing keys
        gpgkeys="`gpg_listmissing`"  # remember, newline-separated

        # Decrement the countdown
        gpgattempts=`expr $gpgattempts - 1`
    done
fi

qprint  # trailing newline

# vim:sw=4 expandtab tw=80
