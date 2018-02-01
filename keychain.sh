#!/bin/sh

# Copyright 1999-2005 Gentoo Foundation
# Copyright 2007 Aron Griffis <agriffis@n01se.net>
# Copyright 2009-2017 Funtoo Solutions, Inc.
# lockfile() Copyright 2009 Parallels, Inc.

# Distributed under the terms of the GNU General Public License v2

# Originally authored by Daniel Robbins <drobbins@gentoo.org>
# Maintained August 2002 - April 2003 by Seth Chandler <sethbc@gentoo.org>
# Maintained and rewritten April 2004 - July 2007 by Aron Griffis <agriffis@n01se.net>
# Maintained July 2009 - Sept 2017 by Daniel Robbins <drobbins@funtoo.org>
# Maintained September 2017 - present by Ryan Harris <x48rph@gmail.com>

version=##VERSION##

PATH="${PATH:-/usr/bin:/bin:/sbin:/usr/sbin:/usr/ucb}"

maintainer="x48rph@gmail.com"
unset mesglog
unset myaction
unset agentsopt
havelock=false
unset hostopt
ignoreopt=false
noaskopt=false
noguiopt=false
nolockopt=false
lockwait=5
openssh=unknown
sunssh=unknown
confhost=unknown
sshconfig=false
confallhosts=false
quickopt=false
quietopt=false
clearopt=false
color=true
inheritwhich=local-once
unset stopwhich
unset timeout
unset ssh_timeout
attempts=1
unset sshavail
unset sshkeys
unset gpgkeys
unset mykeys
keydir="${HOME}/.keychain"
unset envf
evalopt=false
queryopt=false
confirmopt=false
absoluteopt=false
systemdopt=false
unset ssh_confirm
unset GREP_OPTIONS
gpg_prog_name="gpg"

BLUE="[34;01m"
CYAN="[36;01m"
CYANN="[36m"
GREEN="[32;01m"
RED="[31;01m"
PURP="[35;01m"
OFF="[0m"

# GNU awk and sed have regex issues in a multibyte environment.  If any locale
# variables are set, then override by setting LC_ALL
unset pinentry_locale
if [ -n "$LANG$LC_ALL" ] || [ -n "$(locale 2>/dev/null | egrep -v '="?(|POSIX|C)"?$' 2>/dev/null)" ]; then
	# save LC_ALL so that pinentry-curses works right.	This has always worked
	# correctly for me but peper and kloeri had problems with it.
	pinentry_lc_all="$LC_ALL"
	LC_ALL=C
	export LC_ALL
fi

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
	$evalopt && { echo; echo "false;"; }
	exit 1
}

# synopsis: versinfo
# Display the version information
versinfo() {
	qprint
	qprint "   Copyright ${CYANN}2002-2006${OFF} Gentoo Foundation;"
	qprint "   Copyright ${CYANN}2007${OFF} Aron Griffis;"
	qprint "   Copyright ${CYANN}2009-2017${OFF} Funtoo Solutions, Inc;"
	qprint "   lockfile() Copyright ${CYANN}2009${OFF} Parallels, Inc."
	qprint
	qprint " Keychain is free software: you can redistribute it and/or modify"
	qprint " it under the terms of the ${CYANN}GNU General Public License version 2${OFF} as"
	qprint " published by the Free Software Foundation."
	qprint
}

# synopsis: helpinfo
# Display the help information. There's no really good way to use qprint for
# this...
helpinfo() {
	cat >&1 <<EOHELP
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
	case "$(ssh -V 2>&1)" in
		*OpenSSH*) openssh=true ;;
		*Sun?SSH*) sunssh=true ;;
	esac
}

# synopsis: getuser
# Set the global string $me
getuser() {
	# id -un gives euid, which might be different from USER or LOGNAME
	me=$(id -un) || die "Who are you?  id -un doesn't know..."
}

# synopsis: getos
# Set the global string $OSTYPE
getos() {
	OSTYPE=$(uname) || die 'uname failed'
}

# synopsis: verifykeydir
# Make sure the key dir is set up correctly.  Exits on error.
verifykeydir() {
	# Create keydir if it doesn't exist already
	if [ -f "${keydir}" ]; then
		die "${keydir} is a file (it should be a directory)"
	# Solaris 9 doesn't have -e; using -d....
	elif [ ! -d "${keydir}" ]; then
		( umask 0077 && mkdir "${keydir}"; ) || die "can't create ${keydir}"
	fi
}

lockfile() {
	# This function originates from Parallels Inc.'s OpenVZ vpsreboot script

	# Description: This function attempts to acquire the lock. If it succeeds,
	# it returns 0. If it fails, it returns 1. This function retuns immediately
	# and only tries to acquire the lock once.

		tmpfile="$lockf.$$"

		echo $$ >"$tmpfile" 2>/dev/null || exit
		if ln "$tmpfile" "$lockf" 2>/dev/null; then
				rm -f "$tmpfile"
		havelock=true && return 0
		fi
		if kill -0 $(cat $lockf 2>/dev/null) 2>/dev/null; then
				rm -f "$tmpfile"
			return 1
	fi
		if ln "$tmpfile" "$lockf" 2>/dev/null; then
				rm -f "$tmpfile"
		havelock=true && return 0
		fi
		rm -f "$tmpfile" "$lockf" && return 1
}

takelock() {
	# Description: This function calls lockfile() multiple times if necessary
	# to try to acquire the lock. It returns 0 on success and 1 on failure.
	# Change in behavior: if timeout expires, we will forcefully acquire lock.

	[ "$havelock" = "true" ] && return 0
	[ "$nolockopt" = "true" ] && return 0

	# First attempt:
	lockfile && return 0

	counter=0
	mesg "Waiting $lockwait seconds for lock..."
	while [ "$counter" -lt "$(( $lockwait * 2 ))" ]
	do
		lockfile && return 0
		sleep 0.5; counter=$(( $counter + 1 ))
	done 
	rm -f "$lockf" && lockfile && return 0
	return 1
}


# synopsis: droplock
# Drops the lock if we're holding it.
droplock() {
	$havelock && [ -n "$lockf" ] && rm -f "$lockf"
}

# synopsis: findpids [prog]
# Returns a space-separated list of agent pids.
# prog can be ssh or gpg, defaults to ssh.	Note that if another prog is ever
# added, need to pay attention to the length for Solaris compatibility.
findpids() {
	fp_prog=${1-ssh}
	unset fp_psout

	# Different systems require different invocations of ps.  Try to generalize
	# the best we can.	The only requirement is that the agent command name
	# appears in the line, and the PID is the first item on the line.
	[ -n "$OSTYPE" ] || getos

	# Try systems where we know what to do first
	case "$OSTYPE" in
		AIX|*bsd*|*BSD*|CYGWIN|darwin*|Linux|linux-gnu|OSF1)
			fp_psout=$(ps x 2>/dev/null) ;;		# BSD syntax
		HP-UX)
			fp_psout=$(ps -u $me 2>/dev/null) ;; # SysV syntax
		SunOS)
			case $(uname -r) in
				[56]*)
					fp_psout=$(ps -u $me 2>/dev/null) ;; # SysV syntax
				*)
					fp_psout=$(ps x 2>/dev/null) ;;		# BSD syntax
			esac ;;
		GNU|gnu)
			fp_psout=$(ps -g 2>/dev/null) ;;		# GNU Hurd syntax
	esac

	# If we didn't get a match above, try a list of possibilities...
	# The first one will probably fail on systems supporting only BSD syntax.
	if [ -z "$fp_psout" ]; then
		fp_psout=$(UNIX95=1 ps -u $me -o pid,comm 2>/dev/null | grep '^ *[0-9]')
		[ -z "$fp_psout" ] && fp_psout=$(ps x 2>/dev/null)
		[ -z "$fp_psout" ] && fp_psout=$(ps w 2>/dev/null) # Busybox syntax
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
	stop_mypids=$(findpids "$stop_prog")
	[ $? = 0 ] || die

	if [ -z "$stop_mypids" ]; then
		mesg "No $stop_prog-agent(s) found running"
		return 0
	fi

	case "$stopwhich" in
		all)
			kill $stop_mypids >/dev/null 2>&1
			mesg "All ${CYANN}$me${OFF}'s $stop_prog-agents stopped: ${CYANN}$stop_mypids${OFF}"
			;;

		others)
			# Try to handle the case where we *will* inherit a pid
			kill -0 $stop_except >/dev/null 2>&1
			if [ -z "$stop_except" -o $? != 0 -o \
					"$inheritwhich" = local -o "$inheritwhich" = any ]; then
				if [ "$inheritwhich" != none ]; then
					eval stop_except=\$\{inherit_${stop_prog}_agent_pid\}
					kill -0 $stop_except >/dev/null 2>&1
					if [ -z "$stop_except" -o $? != 0 ]; then
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
				mesg "Other ${CYANN}$me${OFF}'s $stop_prog-agents stopped: ${CYANN}$stop_mynewpids${OFF}"
			else
				mesg "No other $stop_prog-agent(s) than keychain's $stop_except found running"
			fi
			;;

		mine)
			if [ $stop_except -gt 0 ] 2>/dev/null; then
				kill $stop_except >/dev/null 2>&1
				mesg "Keychain $stop_prog-agents stopped: ${CYANN}$stop_except${OFF}"
			else
				mesg "No keychain $stop_prog-agent found running"
			fi
			;;
	esac

	# remove pid files if keychain-controlled
	if [ "$stopwhich" != others ]; then
		if [ "$stop_prog" != ssh ]; then
			rm -f "${pidf}-$stop_prog" "${cshpidf}-$stop_prog" "${fishpidf}-$stop_prog" 2>/dev/null
		else
			rm -f "${pidf}" "${cshpidf}" "${fishpidf}" 2>/dev/null
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
				inherit_ssh_auth_sock="$SSH_AUTH_SOCK"
				inherit_ssh_agent_pid="$SSH_AGENT_PID"
			fi

			if [ -n "$SSH2_AUTH_SOCK" ]; then
				inherit_ssh2_auth_sock="$SSH2_AUTH_SOCK"
				inherit_ssh2_agent_pid="$SSH2_AGENT_PID"
			fi
		fi

		if wantagent gpg; then
			if [ -n "$GPG_AGENT_INFO" ]; then
				inherit_gpg_agent_info="$GPG_AGENT_INFO"
				inherit_gpg_agent_pid=$(echo "$GPG_AGENT_INFO" | cut -f2 -d:)
			# GnuPG v.2.1+ removes $GPG_AGENT_INFO
			else
				gpg_socket_dir="${GNUPGHOME:=$HOME/.gnupg}"
				if [ ! -S "${GNUPGHOME:=$HOME/.gnupg}/S.gpg-agent" ]; then
					gpg_socket_dir="${XDG_RUNTIME_DIR}/gnupg"
				fi
				if [ -S "${gpg_socket_dir}/S.gpg-agent" ]; then
					inherit_gpg_agent_pid=$(findpids "${gpg_prog_name}")
					inherit_gpg_agent_info="${gpg_socket_dir}/S.gpg-agent:${inherit_gpg_agent_pid}:1"
				fi
			fi
		fi
	fi
}

# synopsis: validinherit
# Test inherit_* variables for validity
validinherit() {
	vi_agent="$1"
	vi_status=0

	if [ "$vi_agent" = ssh ]; then
		if [ -n "$inherit_ssh_auth_sock" ]; then
			ls "$inherit_ssh_auth_sock" >/dev/null 2>&1
			if [ $? != 0 ]; then
				warn "SSH_AUTH_SOCK in environment is invalid; ignoring it"
				unset inherit_ssh_auth_sock inherit_ssh_agent_pid
				vi_status=1
			fi
		fi

		if [ -n "$inherit_ssh2_auth_sock" ]; then
			ls "$inherit_ssh2_auth_sock" >/dev/null 2>&1
			if [ $? != 0 ]; then
				warn "SSH2_AUTH_SOCK in environment is invalid; ignoring it"
				unset inherit_ssh2_auth_sock inherit_ssh2_agent_pid
				vi_status=1
			fi
		fi

	elif [ "$vi_agent" = gpg ]; then
		if [ -n "$inherit_gpg_agent_pid" ]; then
			kill -0 "$inherit_gpg_agent_pid" >/dev/null 2>&1
			if [ $? != 0 ]; then
				unset inherit_gpg_agent_pid inherit_gpg_agent_info
				warn "GPG_AGENT_INFO in environment is invalid; ignoring it"
				vi_status=1
			fi
		fi
	fi

	return $vi_status
}

# synopsis: catpidf_shell shell agents...
# cat the pid files for the given agents.  This is used by loadagents and also
# for keychain output when --eval is given.
catpidf_shell() {
	case "$1" in
		*/fish|fish) cp_pidf="$fishpidf" ;;
		*csh)		 cp_pidf="$cshpidf" ;;
		*)			 cp_pidf="$pidf" ;;
	esac
	shift

	for cp_a in "$@"; do
		case "${cp_a}" in
			ssh) [ -f "$cp_pidf" ] && cat "$cp_pidf" ;;
			*)	 [ -f "${cp_pidf}-$cp_a" ] && cat "${cp_pidf}-$cp_a" ;;
		esac
		echo
	done

	return 0
}

# synopsis: catpidf agents...
# cat the pid files for the given agents, appropriate for the current value of
# $SHELL.  This is used for keychain output when --eval is given.
catpidf() {
	catpidf_shell "$SHELL" "$@"
}

# synopsis: loadagents agents...
# Load agent variables from $pidf and copy implementation-specific environment
# variables into generic global strings
loadagents() {
	for la_a in "$@"; do
		case "$la_a" in
			ssh)
				unset SSH_AUTH_SOCK SSH_AGENT_PID SSH2_AUTH_SOCK SSH2_AGENT_PID
				eval "$(catpidf_shell sh $la_a)"
				if [ -n "$SSH_AUTH_SOCK" ]; then
					ssh_auth_sock=$SSH_AUTH_SOCK
					ssh_agent_pid=$SSH_AGENT_PID
				elif [ -n "$SSH2_AUTH_SOCK" ]; then
					ssh_auth_sock=$SSH2_AUTH_SOCK
					ssh_agent_pid=$SSH2_AGENT_PID
				else
					unset ssh_auth_sock ssh_agent_pid
				fi
				;;

			gpg)
				unset GPG_AGENT_INFO
				eval "$(catpidf_shell sh $la_a)"
				if [ -n "$GPG_AGENT_INFO" ]; then
					la_IFS="$IFS"  # save current IFS
					IFS=':'		   # set IFS to colon to separate PATH
					set -- $GPG_AGENT_INFO
					IFS="$la_IFS"  # restore IFS
					gpg_agent_pid=$2
				fi
				;;

			*)
				eval "$(catpidf_shell sh $la_a)"
				;;
		esac
	done

	return 0
}

# synopsis: startagent [prog]
# Starts an agent if it isn't already running.
# Requires $ssh_agent_pid
startagent() {
	start_prog=${1-ssh}
	start_proto=${2-${start_prog}}
	unset start_pid
	start_inherit_pid=none
	start_mypids=$(findpids "$start_prog")
	[ $? = 0 ] || die

	# Unfortunately there isn't much way to genericize this without introducing
	# a lot more supporting code/structures.
	if [ "$start_prog" = ssh ]; then
		start_pidf="$pidf"
		start_cshpidf="$cshpidf"
		start_fishpidf="$fishpidf"
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
		start_fishpidf="${fishpidf}-$start_prog"
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
	start_tester="$inheritwhich: $start_mypids $start_fwdflg "
	case "$start_tester" in
		none:*" $start_pid "*|*-once:*" $start_pid "*)
			mesg "Found existing ${start_prog}-agent: ${CYANN}$start_pid${OFF}"
			return 0
			;;

		*:*" $start_inherit_pid "*)
			# This test was postponed until now to prevent generating warnings
			validinherit "$start_prog"
			if [ $? != 0 ]; then
				# inherit_* vars have been removed from the environment.  Try
				# again now
				startagent "$start_prog"
				return $?
			fi
			mesg "Inheriting ${start_prog}-agent ($start_inherit_pid)"
			;;

		*)
			# start_inherit_pid might be "forwarded" which we don't allow with,
			# for example, local-once (the default setting)
			start_inherit_pid=none
			;;
	esac

	# Init the bourne-formatted pidfile
	( umask 0177 && :> "$start_pidf"; )
	if [ $? != 0 ]; then
		rm -f "$start_pidf" "$start_cshpidf" "$start_fishpidf" 2>/dev/null
		error "can't create $start_pidf"
		return 1
	fi

	# Init the csh-formatted pidfile
	( umask 0177 && :> "$start_cshpidf"; )
	if [ $? != 0 ]; then
		rm -f "$start_pidf" "$start_cshpidf" "$start_fishpidf" 2>/dev/null
		error "can't create $start_cshpidf"
		return 1
	fi

	# Init the fish-formatted pidfile
	( umask 0177 && :> "$start_fishpidf"; )
	if [ $? != 0 ]; then
		rm -f "$start_pidf" "$start_cshpidf" "$start_fishpidf" 2>/dev/null
		error "can't create $start_fishpidf"
		return 1
	fi

	# Determine content for files
	unset start_out
	if [ "$start_inherit_pid" = none ]; then

		# Start the agent.
		# Branch again since the agents start differently
		mesg "Starting ${start_prog}-agent..."
		if [ "$start_prog" = ssh ]; then
			start_out=$(ssh-agent ${ssh_timeout})
		elif [ "$start_prog" = gpg ]; then
			if [ -n "${timeout}" ]; then
				gpg_cache_ttl="$(expr $timeout \* 60)"
				start_gpg_timeout="--default-cache-ttl $gpg_cache_ttl --max-cache-ttl $gpg_cache_ttl"
			else
				unset start_gpg_timeout
			fi
			# the 1.9.x series of gpg spews debug on stderr
			start_out=$(gpg-agent --daemon --write-env-file $start_gpg_timeout 2>/dev/null)
		else
			error "I don't know how to start $start_prog-agent (2)"
			return 1
		fi
		if [ $? != 0 -a $? != 2 ]; then
			rm -f "$start_pidf" "$start_cshpidf" "$start_fishpidf" 2>/dev/null
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

	elif [ "$start_prog" = "${gpg_prog_name}" -a -n "$inherit_gpg_agent_info" ]; then
		start_out="GPG_AGENT_INFO=$inherit_gpg_agent_info; export GPG_AGENT_INFO;"

	else
		die "something bad happened"	# should never be here
	fi

	# Add content to pidfiles.
	# Some versions of ssh-agent don't understand -s, which means to
	# generate Bourne shell syntax.  It appears they also ignore SHELL,
	# according to http://bugs.gentoo.org/show_bug.cgi?id=52874
	# So make no assumptions.
	start_out=$(echo "$start_out" | grep -v 'Agent pid')
	case "$start_out" in
		setenv*)
			echo "$start_out" >"$start_cshpidf"
			echo "$start_out" | awk '{print $2"="$3" export "$2";"}' >"$start_pidf"
			;;
		*)
			echo "$start_out" >"$start_pidf"
			echo "$start_out" | sed 's/;.*/;/' | sed 's/=/ /' | sed 's/^/setenv /' >"$start_cshpidf"
			echo "$start_out" | sed 's/;.*/;/' | sed 's/^\(.*\)=\(.*\);/set -e \1; set -x -U \1 \2;/' >"$start_fishpidf"
			;;
	esac

	# Hey the agent should be started now... load it up!
	loadagents "$start_prog"
}

# synopsis: extract_fingerprints
# Extract the fingerprints from standard input, returns space-separated list.
# Utility routine for ssh_l and ssh_f
extract_fingerprints() {
	while read ef_line; do
		case "$ef_line" in
			*\ *\ [0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:*)
				# Sun SSH spits out different things depending on the type of
				# key.	For example:
				#	md5 1024 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00 /home/barney/.ssh/id_dsa(DSA)
				#	2048 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00 /home/barney/.ssh/id_rsa.pub
				echo "$ef_line" | cut -f3 -d' '
				;;
			*\ [0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:*)
				# The more consistent OpenSSH format, we hope
				#	1024 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00 /home/barney/.ssh/id_dsa (DSA)
				echo "$ef_line" | cut -f2 -d' '
				;;
			*\ [A-Z0-9][A-Z0-9]*:[A-Za-z0-9+/][A-Za-z0-9+/]*)
				# The new OpenSSH 6.8+ format,
				#   1024 SHA256:mVPwvezndPv/ARoIadVY98vAC0g+P/5633yTC4d/wXE /home/barney/.ssh/id_dsa (DSA)
				echo "$ef_line" | cut -f2 -d' '
				;;
			*)
				# Fall back to filename.  Note that commercial ssh is handled
				# explicitly in ssh_l and ssh_f, so hopefully this rule will
				# never fire.
				warn "Can't determine fingerprint from the following line, falling back to filename"
				mesg "$ef_line"
				basename "$ef_line" | sed 's/[ (].*//'
				;;
		esac
	done | xargs
}

# synopsis: ssh_l
# Return space-separated list of known fingerprints
ssh_l() {
	sl_mylist=$(ssh-add -l 2>/dev/null)
	sl_retval=$?

	if $openssh; then
		# Error codes:
		#	0  success
		#	1  OpenSSH_3.8.1p1 on Linux: no identities (not an error)
		#	   OpenSSH_3.0.2p1 on HP-UX: can't connect to auth agent
		#	2  can't connect to auth agent
		case $sl_retval in
			0)
				echo "$sl_mylist" | extract_fingerprints
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
		#	0  success (even when there are no keys)
		#	1  error
		case $sl_retval in
			0)
				echo "$sl_mylist" | extract_fingerprints
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
		#	0  success - however might say "The authorization agent has no keys."
		#	1  can't connect to auth agent
		#	2  bad passphrase
		#	3  bad identity file
		#	4  the agent does not have the requested identity
		#	5  unspecified error
		if [ $sl_retval = 0 ]; then
			# Output of ssh-add -l:
			#	The authorization agent has one key:
			#	id_dsa_2048_a: 2048-bit dsa, agriffis@alpha.zk3.dec.com, Fri Jul 25 2003 10:53:49 -0400
			# Since we don't have a fingerprint, just get the filenames *shrug*
			echo "$sl_mylist" | sed '2,$s/:.*//' | xargs
		fi
		return $sl_retval
	fi
}

# synopsis: ssh_f filename
# Return fingerprint for a keyfile
# Requires $openssh or $sunssh
ssh_f() {
	sf_filename="$1"

	if $openssh || $sunssh; then
		realpath_bin="$(command -v realpath)"
		# if private key is symlink and symlink to *.pub is missing:
		if [ -L "$sf_filename" ] && [ ! -z "$realpath_bin" ]; then
			sf_filename="$($realpath_bin $sf_filename)"
		fi
		lsf_filename="$sf_filename.pub"
		if [ ! -f "$lsf_filename" ]; then
			# try to remove extension from private key, *then* add .pub, and see if we now find it:
			if [ -L "$sf_filename" ] && [ ! -z "$realpath_bin" ]; then
				sf_filename="$($realpath_bin $sf_filename)"
			fi
			lsf_filename=$(echo "$sf_filename" | sed 's/\.[^\.]*$//').pub
			if [ ! -f "$lsf_filename" ]; then
			    warn "Cannot find separate public key for $1."
				lsf_filename="$sf_filename"
			fi
		fi
		sf_fing=$(ssh-keygen -l -f "$lsf_filename") || return 1
		echo "$sf_fing" | extract_fingerprints
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

	GPG_TTY=$(tty)

	# Parse $gpgkeys into positional params to preserve spaces in filenames
	set -f			# disable globbing
	glm_IFS="$IFS"	# save current IFS
	IFS="
"					# set IFS to newline
	set -- $gpgkeys
	IFS="$glm_IFS"	# restore IFS
	set +f			# re-enable globbing

	for glm_k in "$@"; do
		# Check if this key is known to the agent.	Don't know another way...
		if echo | env -i GPG_TTY="$GPG_TTY" PATH="$PATH" GPG_AGENT_INFO="$GPG_AGENT_INFO" \
				"${gpg_prog_name}" --no-options --use-agent --no-tty --sign --local-user "$glm_k" -o- >/dev/null 2>&1; then
			# already know about this key
			mesg "Known gpg key: ${CYANN}${glm_k}${OFF}"
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

	echo "$glm_missing"
}

# synopsis: ssh_listmissing
# Uses $sshkeys and $sshavail
# Returns a newline-separated list of keys found to be missing.
ssh_listmissing() {
	unset slm_missing

	# Parse $sshkeys into positional params to preserve spaces in filenames
	set -f			# disable globbing
	slm_IFS="$IFS"	# save current IFS
	IFS="
"					# set IFS to newline
	set -- $sshkeys
	IFS="$slm_IFS"	# restore IFS
	set +f			# re-enable globbing

	for slm_k in "$@"; do
		# Fingerprint current user-specified key
		slm_finger=$(ssh_f "$slm_k") || continue

		# Check if it needs to be added
		case " $sshavail " in
			*" $slm_finger "*)
				# already know about this key
				mesg "Known ssh key: ${CYANN}${slm_k}${OFF}"
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
  for pkeypath in "$@"; do
    mykeys=${mykeys+"$mykeys
"}"$pkeypath"
  done

	# Parse $mykeys into positional params to preserve spaces in filenames
	set -f		   # disable globbing
	pm_IFS="$IFS"  # save current IFS
	IFS="
"				   # set IFS to newline
	set -- $mykeys
	IFS="$pm_IFS"  # restore IFS
	set +f		   # re-enable globbing

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
                        "${gpg_prog_name}" --list-secret-keys "$pm_k" >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                                add_gpgkey "$pm_k" ; continue
			fi
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

# synopsis: setagents
# Check validity of agentsopt
setagents() {
	if [ -n "$agentsopt" ]; then
		agentsopt=$(echo "$agentsopt" | sed 's/,/ /g')
		unset new_agentsopt
		for a in $agentsopt; do
			if command -v ${a}-agent >/dev/null; then
				new_agentsopt="${new_agentsopt+$new_agentsopt }${a}"
			else
				warn "can't find ${a}-agent, removing from list"
			fi
		done
		agentsopt="${new_agentsopt}"
	else
		for a in ssh; do
			command -v ${a}-agent >/dev/null || continue
			agentsopt="${agentsopt+$agentsopt }${a}"
		done
	fi

	if [ -z "$agentsopt" ]; then
		die "no agents available to start"
	fi
}

# synopsis: confpath
# Return private key path if found in ~/.ssh/config SSH configuration file.
# Input: the name of the host we would like to connect to.
confpath() {
	h=""
	while IFS= read -r line; do
		# get the Host directives
		case $line in
			*"Host "*) h=$(echo $line | awk '{print $2}') ;;
		esac
		case $line in
			*IdentityFile*)
			if [ $h = "$1" ]; then
				echo $line | awk '{print $2}'
				break
			fi
		esac
	done < ~/.ssh/config
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
			# As of version 2.5, --stop takes an argument.	For the sake of
			# backward compatibility, only eat the arg if it's one we recognize.
			if [ "$2" = mine ]; then
				stopwhich=mine; shift
			elif [ "$2" = others ]; then
				stopwhich=others; shift
			elif [ "$2" = all ]; then
				stopwhich=all; shift
			else
				# backward compat
				stopwhich=all-warn
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
		--clear)
			clearopt=true
			$quickopt && die "--quick and --clear are not compatible"
			;;
		--confirm)
			confirmopt=true
			;;
		--absolute)
			absoluteopt=true
			;;
		--dir)
			shift
			case "$1" in
				*/.*) keydir="$1" ;;
				'')   die "--dir requires an argument" ;;
				*)
					if $absoluteopt; then
						keydir="$1"
					else
						keydir="$1/.keychain" # be backward-compatible
					fi
					;;
			esac
			;;
		--env)
			shift
			if [ -z "$1" ]; then
				die "--env requires an argument"
			else
				envf="$1"
			fi
			;;
		--eval)
			evalopt=true
			;;
		--list|-l)
			ssh-add -l
			quietopt=true
			;;
		--list-fp|-L)
			ssh-add -L
			quietopt=true
			;;
		--query)
			queryopt=true
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
				die "--lockwait requires an argument zero or greater."
			fi
			;;
		--quick|-Q)
			quickopt=true
			$clearopt && die "--quick and --clear are not compatible"
			;;
		--quiet|-q)
			quietopt=true
			;;
		--confhost|-c)
			if [ -e ~/.ssh/config ]; then
				sshconfig=true
				confhost="$2"
			else
				warn "~/.ssh/config not found; --confhost/-c option ignored."
			fi
			;;
    --confallhosts|-C)
			if [ -e ~/.ssh/config ]; then
				sshconfig=true
        confallhosts=true
			else
				warn "~/.ssh/config not found; --confallhosts/-C option ignored."
			fi
			;;
		--nocolor)
			color=false
			;;
		--timeout)
			shift
			if [ "$1" -gt 0 ] 2>/dev/null; then
				timeout=$1
			else
				die "--timeout requires a numeric argument greater than zero"
			fi
			;;
		--systemd)
			systemdopt=true
			;;
		--gpg2)
		    gpg_prog_name="gpg2"
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
			zero=$(basename "$0")
			echo "$zero: unknown option $1" >&2
			$evalopt && { echo; echo "false;"; }
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
# .ssh-agent file with csh-compatible syntax. fishpidf is the .ssh-agent
# file with fish-compatible syntax. lockf is the lockfile, used
# to serialize the execution of multiple ssh-agent processes started
# simultaneously
[ -z "$hostopt" ] && hostopt="${HOSTNAME}"
[ -z "$hostopt" ] && hostopt=$(uname -n 2>/dev/null || echo unknown)
pidf="${keydir}/${hostopt}-sh"
cshpidf="${keydir}/${hostopt}-csh"
fishpidf="${keydir}/${hostopt}-fish"
olockf="${keydir}/${hostopt}-lock"
lockf="${keydir}/${hostopt}-lockf"

# Read the env snippet (especially for things like PATH, but could modify
# basically anything)
if [ -z "$envf" ]; then
	envf="${keydir}/${hostopt}-env"
	[ -f "$envf" ] || envf="${keydir}/env"
	[ -f "$envf" ] || unset envf
fi
if [ -n "$envf" ]; then
	. "$envf"
fi

# Don't use color if there's no terminal on stderr
if [ -n "$OFF" ]; then
	tty <&2 >/dev/null 2>&1 || color=false
fi

#disable color if necessary, right before our initial newline

$color || unset BLUE CYAN CYANN GREEN PURP OFF RED

qprint #initial newline
mesg "${PURP}keychain ${OFF}${CYANN}${version}${OFF} ~ ${GREEN}http://www.funtoo.org${OFF}"
[ "$myaction" = version ] && { versinfo; exit 0; }
[ "$myaction" = help ] && { versinfo; helpinfo; exit 0; }

# Set up traps
# Don't use signal names because they don't work on Cygwin.
if $clearopt; then
	trap '' 2	# disallow ^C until we've had a chance to --clear
	trap 'droplock; exit 1' 1 15	# drop the lock on signal
	trap 'droplock; exit 0' 0		# drop the lock on exit
else
	# Don't use signal names because they don't work on Cygwin.
	trap 'droplock; exit 1' 1 2 15	# drop the lock on signal
	trap 'droplock; exit 0' 0		# drop the lock on exit
fi

setagents						# verify/set $agentsopt
verifykeydir					# sets up $keydir
wantagent ssh && testssh		# sets $openssh and $sunssh
getuser							# sets $me

# Inherit agent info from the environment before loadagents wipes it out.
# Always call this since it checks $inheritopt and sets variables accordingly.
inheritagents

# --stop: kill the existing ssh-agent(s) and quit
if [ -n "$stopwhich" ]; then
	if [ "$stopwhich" = all-warn ]; then
		warn "--stop without an argument is deprecated; see --help"
		stopwhich=all
	fi
	takelock || die
	if [ "$stopwhich" = mine -o "$stopwhich" = others ]; then
		loadagents $agentsopt
	fi
	for a in $agentsopt; do
		stopagent $a
	done
	if [ "$stopwhich" != others ]; then
		qprint
		exit 0					# stopagent is always successful
	fi
fi

# Note regarding locking: if we're trying to be quick, then don't take the lock.
# It will be taken later if we discover we can't be quick.
if $quickopt; then
	loadagents $agentsopt		# sets ssh_auth_sock, ssh_agent_pid, etc
	unset nagentsopt
	for a in $agentsopt; do
		needstart=true

		# Trying to be quick has a price... If we discover the agent isn't running,
		# then we'll have to check things again (in startagent) after taking the
		# lock.  So don't do the initial check unless --quick was specified.
		if [ $a = ssh ]; then
			sshavail=$(ssh_l)	# try to use existing agent
								# 0 = found keys, 1 = no keys, 2 = no agent
			if [ $? = 0 -o \( $? = 1 -a -z "$mykeys" \) ]; then
				mesg "Found existing ssh-agent: ${CYANN}$ssh_agent_pid${OFF}"
				needstart=false
			fi
		elif [ $a = gpg ]; then
			# not much way to be quick on this
			if [ -n "$gpg_agent_pid" ]; then
				case " $(findpids "${gpg_prog_name}") " in
					*" $gpg_agent_pid "*)
						mesg "Found existing gpg-agent: ${CYANN}$gpg_agent_pid${OFF}"
						needstart=false ;;
				esac
			fi
		fi

		if $needstart; then
			nagentsopt="$nagentsopt $a"
		elif $evalopt; then
			catpidf $a
		fi
	done
	agentsopt="$nagentsopt"
fi

# If there are no agents remaining, then bow out now...
[ -n "$agentsopt" ] || { qprint; exit 0; }

# --timeout translates almost directly to ssh-add/ssh-agent -t, but ssh.com uses
# minutes and OpenSSH uses seconds
if [ -n "$timeout" ] && wantagent ssh; then
	ssh_timeout=$timeout
	if $openssh || $sunssh; then
		ssh_timeout=$(expr $ssh_timeout \* 60)
	fi
	ssh_timeout="-t $ssh_timeout"
fi

# There are agents remaining to start, and we now know we can't be quick.  Take
# the lock before continuing
takelock || die
loadagents $agentsopt
unset nagentsopt
for a in $agentsopt; do
	if $queryopt; then
		catpidf_shell sh $a | cut -d\; -f1
	elif startagent $a; then
		nagentsopt="${nagentsopt+$nagentsopt }$a"
		$evalopt && catpidf $a
	fi
done
agentsopt="$nagentsopt"

# If we are just querying the services, exit.
$queryopt && exit 0

# If there are no agents remaining, then duck out now...
[ -n "$agentsopt" ] || { qprint; exit 0; }

# --confirm translates to ssh-add -c
if $confirmopt && wantagent ssh; then
	if $openssh || $sunssh; then
		ssh_confirm=-c
	else
		warn "--confirm only works with OpenSSH"
	fi
fi

# --clear: remove all keys from the agent(s)
if $clearopt; then
	for a in ${agentsopt}; do
		if [ $a = ssh ]; then
			sshout=$(ssh-add -D 2>&1)
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
	trap 'droplock' 2				# done clearing, safe to ctrl-c
fi

if $systemdopt; then
	for a in $agentsopt; do
		systemctl --user set-environment $( catpidf_shell sh $a | cut -d\; -f1 )
	done
fi

# --noask: "don't ask for keys", so we're all done
$noaskopt && { qprint; exit 0; }

# If the --confhost or the --confallhosts option used, and the .ssh/config
# file exists, either load host key or all keys defined
if $sshconfig; then
  if $confallhosts; then
    # If the --confallhosts option used, load all the private keys defined in
    # the .ssh/config file and add them to ssh-add
    while IFS= read -r line; do
      case $line in
        *IdentityFile*)
        currentpath="$(echo $line | awk '{print $2}')"
        eval currentpath=$currentpath
        pkeypaths=${pkeypaths+"$pkeypaths
"}"$currentpath"   
      esac
    done < ~/.ssh/config
  else
    # If the --confhost option is used, find the private key through 
    # .ssh/config file and load it with ssh-add
    pkeypaths=$(confpath "$confhost")
	  eval pkeypaths=$pkeypaths
  fi
fi

# Parse $mykeys into ssh vs. gpg keys; it may be necessary in the future to
# differentiate on the cmdline
parse_mykeys "$pkeypaths" || die

# Load ssh keys
if wantagent ssh; then
	sshavail=$(ssh_l)				# update sshavail now that we're locked
	if [ "$myaction" = "list" ]; then
		for key in $sshavail end; do
			[ "$key" = "end" ] && continue
			echo "$key"
		done
	else
		sshkeys="$(ssh_listmissing)"		# cache list of missing keys, newline-separated
		sshattempts=$attempts
		savedisplay="$DISPLAY"

		# Attempt to add the keys
		while [ -n "$sshkeys" ]; do

			mesg "Adding ${CYANN}"$(echo "$sshkeys" | wc -l)"${OFF} ssh key(s): $(echo $sshkeys)"

			# Parse $sshkeys into positional params to preserve spaces in filenames.
			# This *must* happen after any calls to subroutines because pure Bourne
			# shell doesn't restore "$@" following a call.	Eeeeek!
			set -f			# disable globbing
			old_IFS="$IFS"	# save current IFS
			IFS="
	"						# set IFS to newline
			set -- $sshkeys
			IFS="$old_IFS"	# restore IFS
			set +f			# re-enable globbing

			if $noguiopt || [ -z "$SSH_ASKPASS" -o -z "$DISPLAY" ]; then
				unset DISPLAY		# DISPLAY="" can cause problems
				unset SSH_ASKPASS	# make sure ssh-add doesn't try SSH_ASKPASS
				sshout=$(ssh-add ${ssh_timeout} ${ssh_confirm} "$@" 2>&1)
			else
				sshout=$(ssh-add ${ssh_timeout} ${ssh_confirm} "$@" 2>&1 </dev/null)
			fi
			if [ $? = 0 ]
		then
			blurb=""
			[ -n "$timeout" ] && blurb="life=${timeout}m"
			[ -n "$timeout" ] && $confirmopt && blurb="${blurb},"
			$confirmopt && blurb="${blurb}confirm"
			[ -n "$blurb" ] && blurb=" (${blurb})"
			mesg "ssh-add: Identities added: $(echo $sshkeys)${blurb}"
			break
		fi
			if [ $sshattempts = 1 ]; then
				die "Problem adding; giving up"
			else
				warn "Problem adding; trying again"
			fi

			# Update the list of missing keys
			sshavail=$(ssh_l)
			[ $? = 0 ] || die "problem running ssh-add -l"
			sshkeys="$(ssh_listmissing)"  # remember, newline-separated

			# Decrement the countdown
			sshattempts=$(expr $sshattempts - 1)
		done

		[ -n "$savedisplay" ] && DISPLAY="$savedisplay"
	fi
fi

# Load gpg keys
if wantagent gpg; then
	gpgkeys="$(gpg_listmissing)"		# cache list of missing keys, newline-separated
	gpgattempts=$attempts

	$noguiopt && unset DISPLAY
	[ -n "$DISPLAY" ] || unset DISPLAY	# DISPLAY="" can cause problems
	GPG_TTY=$(tty) ; export GPG_TTY		# fall back to ncurses pinentry

	# Attempt to add the keys
	while [ -n "$gpgkeys" ]; do
		tryagain=false

		mesg "Adding ${BLUE}"$(echo "$gpgkeys" | wc -l)"${OFF} gpg key(s): $(echo $gpgkeys)"

		# Parse $gpgkeys into positional params to preserve spaces in filenames.
		# This *must* happen after any calls to subroutines because pure Bourne
		# shell doesn't restore "$@" following a call.	Eeeeek!
		set -f			# disable globbing
		old_IFS="$IFS"	# save current IFS
		IFS="
"						# set IFS to newline
		set -- $gpgkeys
		IFS="$old_IFS"	# restore IFS
		set +f			# re-enable globbing

		for k in "$@"; do
			echo | env LC_ALL="$pinentry_lc_all" \
				"${gpg_prog_name}" --no-options --use-agent --no-tty --sign --local-user "$k" -o- >/dev/null 2>&1
			[ $? != 0 ] && tryagain=true
		done
		$tryagain || break

		if [ $gpgattempts = 1 ]; then
			die "Problem adding (is pinentry installed?); giving up"
		else
			warn "Problem adding; trying again"
		fi

		# Update the list of missing keys
		gpgkeys="$(gpg_listmissing)"  # remember, newline-separated

		# Decrement the countdown
		gpgattempts=$(expr $gpgattempts - 1)
	done
fi

qprint	# trailing newline

# vim:sw=4 noexpandtab tw=120
