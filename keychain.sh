#!/bin/sh
# Copyright 1999-2003 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Author: Daniel Robbins <drobbins@gentoo.org>
# Previous Maintainer: Seth Chandler <sethbc@gentoo.org>
# Current Maintainer: Aron Griffis <agriffis@gentoo.org>
# $Header$

version=2.4.1

PATH="/usr/bin:/bin:/sbin:/usr/sbin:/usr/ucb:${PATH}"

maintainer="agriffis@gentoo.org"
zero=`basename "$0"`
mesglog=''
myaction=''
agentsopt=''
hostopt=''
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
timeout=''
attempts=3
myavail=''
mykeys=''
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
    qprint "${GREEN}KeyChain ${version}; ${BLUE}http://www.gentoo.org/projects/keychain${OFF}"
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
    # Honor --nolock
    if $nolockopt; then
        lockf=''
        return 0
    fi

    tl_faking=false
    tl_oldpid=''

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
        tl_error=`ln -s $$ "$lockf" 2>&1` && return 0

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

    # OS X requires special handling.  It returns a false positive with 
    # "ps -u $me" but is running bash so we can check for it via OSTYPE
    case "$OSTYPE" in darwin*) fp_psout=`ps x 2>/dev/null` ;; esac

    # SysV syntax will work on Cygwin, Linux, HP-UX and Tru64 
    # (among others)
    [ -z "$fp_psout" ] && fp_psout=`ps -u $me 2>/dev/null`

    # BSD syntax for others
    [ -z "$fp_psout" ] && fp_psout=`ps x 2>/dev/null`

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
    stop_mypids=`findpids "$stop_prog"`
    [ $? = 0 ] || die

    kill $stop_mypids >/dev/null 2>&1

    if [ -n "$stop_mypids" ]; then
        mesg "All $me's $stop_prog-agent(s) ($stop_mypids) are now stopped."
    else
        mesg "No $stop_prog-agent(s) found running."
    fi

    if [ "$stop_prog" != ssh ]; then
        rm -f "${pidf}-$stop_prog" "${cshpidf}-$stop_prog" 2>/dev/null
    else
        rm -f "${pidf}" "${cshpidf}" 2>/dev/null
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
        ssh_auth_sock_name=SSH_AUTH_SOCK
        ssh_agent_pid_name=SSH_AGENT_PID
    elif [ -n "$SSH2_AUTH_SOCK" ]; then
        ssh_auth_sock=$SSH2_AUTH_SOCK
        ssh_agent_pid=$SSH2_AGENT_PID
        ssh_auth_sock_name=SSH2_AUTH_SOCK
        ssh_agent_pid_name=SSH2_AGENT_PID
    else
        unset ssh_auth_sock ssh_agent_pid ssh_auth_sock_name ssh_agent_pid_name
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
    start_mypids=`findpids "$start_prog"`
    [ $? = 0 ] || die

    # Unfortunately there isn't much way to genericize this without introducing
    # a lot more supporting code/structures.
    if [ "$start_prog" = ssh ]; then
        start_pidf="$pidf"
        start_cshpidf="$cshpidf"
        start_pid="$ssh_agent_pid"
    else
        start_pidf="${pidf}-$start_prog"
        start_cshpidf="${cshpidf}-$start_prog"
        if [ "$start_prog" = gpg ]; then
            start_pid="$gpg_agent_pid"
        else
            error "I don't know how to start $start_prog-agent (1)"
            return 1
        fi
    fi
    [ "$start_pid" -gt 0 ] 2>/dev/null || start_pid=none

    # Check for an existing agent
    case " $start_mypids " in
        *" $start_pid "*)
            mesg "Found existing ${start_prog}-agent at PID $start_pid"
            return 0
            ;;
    esac

    kill $start_mypids >/dev/null 2>&1 && \
    mesg "All previously running $start_prog-agent(s) have been stopped."

    # Init the bourne-formatted pidfile
    mesg "Initializing $start_pidf file..."
    :> "$start_pidf" && chmod 0600 "$start_pidf"
    if [ $? != 0 ]; then
        rm -f "$start_pidf" "$start_cshpidf" 2>/dev/null
        error "can't create ${start_pidf}"
        return 1
    fi

    # Init the csh-formatted pidfile
    mesg "Initializing ${start_cshpidf} file..."
    :> "$start_cshpidf" && chmod 0600 "$start_cshpidf"
    if [ $? != 0 ]; then
        rm -f "$start_pidf" "$start_cshpidf" 2>/dev/null
        error "can't create ${start_cshpidf}"
        return 1
    fi

    # Start the agent.
    # Branch again since the agents start differently
    mesg "Starting ${start_prog}-agent"
    if [ "$start_prog" = ssh ]; then
        start_out=`ssh-agent`
    elif [ "$start_prog" = gpg ]; then
        if [ -n "${timeout}" ]; then
            start_gpg_timeout=`expr ${timeout} \* 60`
            start_gpg_timeout="--default-cache-ttl ${start_gpg_timeout}"
        else
            start_gpg_timeout=''
        fi
        # the 1.9.x series of gpg spews debug on stderr
        start_out=`gpg-agent --daemon ${start_gpg_timeout} 2>/dev/null`
    else
        error "I don't know how to start $start_prog-agent (2)"
        return 1
    fi
    if [ $? != 0 ]; then
        rm -f "$start_pidf" "$start_cshpidf" 2>/dev/null
        error "Failed to start ${start_prog}-agent"
        return 1
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

# synopsis: listmissing
# Uses $mykeys and $myavail
# Returns a newline-separated list of keys found to be missing.
listmissing() {
    lm_missing=''

    # Parse $mykeys into positional params to preserve spaces in filenames
    set -f;        # disable globbing
    lm_IFS="$IFS"  # save current IFS
    IFS="
"                  # set IFS to newline
    set -- $mykeys
    IFS="$lm_IFS"  # restore IFS
    set +f         # re-enable globbing

    for lm_k in "$@"; do
        # Search for the keyfile
        if [ -f "$lm_k" ]; then
            lm_kfile="$lm_k"
        elif [ -f "$HOME/.ssh/$lm_k" ]; then
            lm_kfile="$HOME/.ssh/$lm_k"
        elif [ -f "$HOME/.ssh2/$lm_k" ]; then
            lm_kfile="$HOME/.ssh2/$lm_k"
        else
            $ignoreopt || warn "can't find $lm_k; skipping"
            continue
        fi

        # Fingerprint current user-specified key
        lm_finger=`ssh_f "$lm_kfile"` || continue

        # Check if it needs to be added
        case " $myavail " in
            *" $lm_finger "*)
                # already know about this key
                mesg "Known key: ${BLUE}${lm_k}${OFF}"
                ;;
            *)
                # need to add this key
                if [ -z "$lm_missing" ]; then
                    lm_missing="$lm_kfile"
                else
                    lm_missing="$lm_missing
$lm_kfile"
                fi
                ;;
        esac
    done

    echo "$lm_missing"
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
        new_agentsopt=''
        for a in $agentsopt; do
            if in_path ${a}-agent >/dev/null; then
                new_agentsopt="${new_agentsopt}${new_agentsopt+ }${a}"
            else
                warn "can't find ${a}-agent, removing from list"
            fi
        done
        agentsopt="${new_agentsopt}"
    else
        for a in ssh gpg; do
            in_path ${a}-agent >/dev/null || continue
            agentsopt="${agentsopt}${agentsopt+ }${a}"
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
            setaction stop 
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
            ;;
        --host)
            shift
            hostopt="$1"
            ;;
        --ignore-missing)
            ignoreopt=true
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

# --stop: kill the existing ssh-agent(s) and quit
if [ "$myaction" = stop ]; then 
    takelock || die
    for a in $agentsopt; do
        stopagent $a
    done
    qprint
    exit 0                      # stopagent is always successful
fi

# Note regarding locking: if we're trying to be quick, then don't take the lock.
# It will be taken later if we discover we can't be quick.  On the other hand,
# if we're not trying to be quick, then take the lock now to avoid a race
# condition.
$quickopt || takelock || die    # take lock to manipulate keys/pids/files
loadagents                      # sets ssh_auth_sock, ssh_agent_pid, etc
for a in $agentsopt; do
    retval=1
    if [ $a = ssh ]; then
        myavail=`ssh_l`         # try to use existing agent
                                # 0 = found keys, 1 = no keys, 2 = no agent
        if [ $? = 0 -o \( $? = 1 -a -z "$mykeys" \) ]; then
            mesg "Found existing ssh-agent ($ssh_agent_pid)"
            retval=0
        fi
    elif [ $a = gpg ]; then
        if [ -n "$gpg_agent_pid" ]; then
            mesg "Found existing gpg-agent ($gpg_agent_pid)"
            retval=0
        fi
    else
        die "I don't know how to start ${a}-agent (3)"
    fi

    if [ $retval = 0 ]; then
        running="${agentsopt}${agentsopt+ }${a}"
    else
        $quickopt && { takelock || die; }
        startagent $a || die
        quickopt=false
    fi
done
if $quickopt && [ "$running" = "$agentsopt" ]; then
    exit 0
fi

# --timeout translates almost directly to ssh-add -t, but ssh.com uses
# minutes and OpenSSH uses seconds
if [ -n "$timeout" ] && wantagent ssh; then
    ssh_timeout=$timeout
    if $openssh || $sunssh; then
        ssh_timeout=`expr $ssh_timeout \* 60`
    fi
    ssh_timeout="-t ${ssh_timeout}"
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
        else
            warn "--clear not supported for ${a}-agent"
        fi
    done
fi
trap 'droplock' 2               # done clearing, safe to ctrl-c

# --noask: "don't ask for keys", so we're all done
$noaskopt && { qprint; exit 0; }

if wantagent ssh; then
    myavail=`ssh_l`                 # update myavail now that we're locked
    mykeys="`listmissing`"          # cache list of missing keys, newline-separated

    # Attempt to add the keys
    while [ -n "$mykeys" ]; do

        mesg "Adding ${BLUE}"`echo "$mykeys" | wc -l`"${OFF} key(s)..."

        # Parse $mykeys into positional params to preserve spaces in filenames.
        # This *must* happen after any calls to subroutines because pure Bourne
        # shell doesn't restore "$@" following a call.  Eeeeek!
        set -f;            # disable globbing
        old_IFS="$IFS"     # save current IFS
        IFS="
"                          # set IFS to newline
        set -- $mykeys
        old_IFS="$lm_IFS"  # restore IFS
        set +f             # re-enable globbing

        if $noguiopt || [ -z "$SSH_ASKPASS" -o -z "$DISPLAY" ]; then
            unset SSH_ASKPASS   # make sure ssh-add doesn't try SSH_ASKPASS
            sshout=`ssh-add ${ssh_timeout} "$@"`
        else
            sshout=`ssh-add ${ssh_timeout} "$@" </dev/null`
        fi
        [ $? = 0 ] && break

        if [ $attempts = 1 ]; then
            die "Problem adding; giving up"
        else
            warn "Problem adding; trying again"
        fi

        # Update the list of missing keys
        myavail=`ssh_l`
        [ $? = 0 ] || die "problem running ssh-add -l"
        mykeys="`listmissing`"  # remember, newline-separated

        # Decrement the countdown
        attempts=`expr $attempts - 1`
    done
fi

qprint  # trailing newline

# vim:sw=4 expandtab tw=80
