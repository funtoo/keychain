#!/bin/sh

versinfo() {
	qprint
	qprint "   Copyright ${CYANN}2009-##CUR_YEAR##${OFF} Daniel Robbins, Funtoo Solutions, Inc;"
	qprint "   lockfile() Copyright ${CYANN}2009${OFF} Parallels, Inc."
	qprint "   Copyright ${CYANN}2007${OFF} Aron Griffis;"
	qprint "   Copyright ${CYANN}2002-2006${OFF} Gentoo Foundation;"
	qprint
	qprint " Keychain is free software: you can redistribute it and/or modify"
	qprint " it under the terms of the ${CYANN}GNU General Public License version 2${OFF} as"
	qprint " published by the Free Software Foundation."
	qprint
}

version=##VERSION##

if [ "$PATH" ]
then
	PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin:/usr/ucb
else
	PATH=/usr/bin:/bin:/sbin:/usr/sbin:/usr/ucb
fi

unset pidfile_out
unset myaction
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
allow_inherited=true
color=true
unset stopwhich
unset timeout
unset ssh_agent_socket
unset ssh_timeout
attempts=1
unset sshavail
unset sshkeys
unset gpgkeys
unset mykeys
keydir="${HOME}/.keychain"
unset envf
evalopt=false
confirmopt=false
absoluteopt=false
systemdopt=false
unset ssh_confirm
unset GREP_OPTIONS
gpg_prog_name="gpg"
gpg_started=false
ssh_allow_forwarded=false
ssh_allow_gpg=false
ssh_spawn_gpg=false
debugopt=false

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
if [ -n "$LANG$LC_ALL" ] || locale 2>/dev/null | grep -E -qv '="?(|POSIX|C)"?$' 2>/dev/null; then
	# save LC_ALL so that pinentry-curses works right.	This has always worked
	# correctly for me but peper and kloeri had problems with it.
	pinentry_lc_all="$LC_ALL"
	LC_ALL=C
	export LC_ALL
fi

qprint() {
	$quietopt || echo "$*" >&2
}

mesg() {
	qprint " ${GREEN}*${OFF} $*"
}

warn() {
	echo " ${RED}* Warning${OFF}: $*" >&2
}

debug() {
	$debugopt && echo "${CYAN}debug> $*${OFF}" >&2
}

error() {
	echo " ${RED}* Error${OFF}: $*" >&2
}

die() {
	[ -n "$1" ] && error "$*"
	qprint
	$evalopt && { echo; echo "false;"; }
	exit 1
}

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
	# See if gpg-agent is available and provides ssh-agent functionality:
	if $ssh_spawn_gpg; then
		if  ! out="$(gpg-agent --help | grep enable-ssh-support)" || [ -z "$out" ]; then
			warn "gpg-agent ssh functionality not available; not using..."
			ssh_spawn_gpg=false
		fi
	fi
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
	# Can we write to the keydir? - The ( ) subshell is intentional! We don't want to change the umask globally!
	if ! ( umask 0177 && :> "$pidf.foo" ); then
		die "can't write inside $pidf"
	else
		rm -f "$pidf.foo"
	fi
}

lockfile() {
	# This function originates from Parallels Inc.'s OpenVZ vpsreboot script.

	# Description: This function attempts to acquire the lock. If it succeeds,
	# it returns 0. If it fails, it returns 1. This function retuns immediately
	# and only tries to acquire the lock once.

	tmpfile="$lockf.$$"

	echo $$ >"$tmpfile" 2>/dev/null || exit
	if ln "$tmpfile" "$lockf" 2>/dev/null; then
		rm -f "$tmpfile"
		havelock=true && return 0
	fi
	if kill -0 "$(cat "$lockf" 2>/dev/null)" 2>/dev/null; then
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
	while [ "$counter" -lt "$(( lockwait * 10 ))" ]
	do
		lockfile && return 0
		sleep 0.1; counter=$(( counter + 1 ))
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
	if [ -z "$OSTYPE" ]; then
		OSTYPE=$(uname) || die 'uname failed'
	fi

	# Try systems where we know what to do first
	case "$OSTYPE" in
		AIX|*bsd*|*BSD*|CYGWIN|darwin*|Linux|linux-gnu|OSF1)
			fp_psout=$(ps x 2>/dev/null) ;;		# BSD syntax
		HP-UX)
			fp_psout=$(ps -u "$me" 2>/dev/null) ;; # SysV syntax
		SunOS)
			case $(uname -r) in
				[56]*)
					fp_psout=$(ps -u "$me" 2>/dev/null) ;; # SysV syntax
				*)
					fp_psout=$(ps x 2>/dev/null) ;; # BSD syntax
			esac ;;
		GNU|gnu)
			fp_psout=$(ps -g 2>/dev/null) ;; # GNU Hurd syntax
	esac

	# If we didn't get a match above, try a list of possibilities...
	# The first one will probably fail on systems supporting only BSD syntax.
	if [ -z "$fp_psout" ]; then
		# shellcheck disable=SC2009
		fp_psout=$(UNIX95=1 ps -u "$me" -o pid,comm 2>/dev/null | grep '^ *[0-9]+')
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
	error "Please report to https://github.com/funtoo/keychain/issues."
	return 1
}

stop_ssh_agents() {
	mesg "Stopping ssh-agent(s)..."
	takelock || die
	[ "$stopwhich" != all ] && eval "$(catpidf_shell sh)" # get SSH_AGENT_PID if defined
	ssh_pids=$(findpids ssh) || die
	if [ -z "$ssh_pids" ]; then
		mesg "No ssh-agent(s) found running"
	elif [ "$stopwhich" = all ]; then
		# shellcheck disable=SC2086
		kill $ssh_pids >/dev/null 2>&1
		mesg "All ${CYANN}$me${OFF}'s ssh-agents stopped: ${CYANN}$ssh_pids${OFF}"
	elif [ -n "$SSH_AGENT_PID" ]; then
		if [ "$stopwhich" = mine ]; then
			kill "$SSH_AGENT_PID" >/dev/null 2>&1
			mesg "Keychain ssh-agents stopped: ${CYANN}$SSH_AGENT_PID${OFF}"
		else # others
			for ssh_pid in $ssh_pids; do
				[ "$ssh_pid" = "$SSH_AGENT_PID" ] && continue
				kill "$ssh_pid" >/dev/null 2>&1
				killed_pids="$killed_pids $ssh_pid"
			done
			mesg "Other ${CYANN}$me${OFF}'s ssh-agents stopped:${CYANN}$killed_pids${OFF}"
		fi
	else
		mesg "No keychain ssh-agent found running"
	fi

	# remove pid files if keychain-controlled
	if [ "$stopwhich" != others ]; then
		rm -f "${pidf}" "${cshpidf}" "${fishpidf}" 2>/dev/null
	fi
	qprint && exit 0
}

# synopsis: catpidf_shell shell
# cat the pid file for the specified shell.
catpidf_shell() {
	case "$1" in
		*/fish|fish) cp_pidf="$fishpidf" ;;
		*csh)		 cp_pidf="$cshpidf" ;;
		*)			 cp_pidf="$pidf" ;;
	esac
	shift
	[ ! -f "$cp_pidf" ] && return 1
	[ -f "$cp_pidf" ] && cat "${cp_pidf}" && echo && return 0
}

startagent_gpg() {
	if $gpg_started; then
		return 0
	else
		gpg_started=true
	fi
	if gpg_agent_sock="$( echo "GETINFO socket_name" | gpg-connect-agent --no-autostart 2>/dev/null | head -n1 | sed -n 's/^D //;1p' )" && [ -S "$gpg_agent_sock" ]; then
		mesg "Using existing gpg-agent: ${CYANN}$gpg_agent_sock${OFF}"
	else
		gpg_opts="--daemon"
		[ -n "${timeout}" ] && gpg_opts="$gpg_opts --default-cache-ttl $(( timeout * 60 )) --max-cache-ttl $(( timeout * 60 ))"
		$ssh_spawn_gpg && gpg_opts="$gpg_opts --enable-ssh-support"
		mesg "Starting gpg-agent..."
		# shellcheck disable=SC2086 # this is intentionalh
		pidfile_out="$(gpg-agent --sh $gpg_opts)"
		return $?
	fi
}

ssh_envcheck() {
	envcheck_echo=true # if false, don't print out any warnings as we are doing a pre-check...
	[ "$2" = "quiet" ] && envcheck_echo=false
	
	# Initial short-circuits for known abort cases:
	
	[ -z "$SSH_AUTH_SOCK" ] && return 1
	if [ ! -S "$SSH_AUTH_SOCK" ]; then
		$envcheck_echo && warn "SSH_AUTH_SOCK in $1 is invalid; ignoring it"
		unset SSH_AUTH_SOCK && return 1
	fi

	# Throw away the PID with a devug warning if it's invalid:

	if [ -n "$SSH_AGENT_PID" ] && ! kill -0 "$SSH_AGENT_PID" >/dev/null 2>&1; then
		unset SSH_AGENT_PID && debug "SSH_AGENT_PID in $1 is invalid; ignoring it"
	fi

	# Now, find potential agents:

	if [ -z "$SSH_AGENT_PID" ]; then

		# There are some cases where we can accept a socket without an associated SSH_AGENT_PID:

		if gpg_socket="$( echo "GETINFO ssh_socket_name" | gpg-connect-agent --no-autostart 2>/dev/null | head -n1 | sed -n 's/^D //;1p' )"; then
			if [ "$gpg_socket" = "$SSH_AUTH_SOCK" ]; then
				if $ssh_allow_gpg; then
					mesg "Using ssh-agent ($1): ${CYANN}$gpg_socket${OFF} (GnuPG)" && return 0
				else
					unset SSH_AUTH_SOCK && debug "Ignoring SSH_AUTH_SOCK -- this is the GnuPG-supplied socket" && return 1
				fi
			fi
		fi

		if $ssh_allow_forwarded; then
			SSH_AGENT_PID="forwarded"
			mesg "Using ${GREEN}forwarded${OFF} ssh-agent: ${GREEN}$SSH_AUTH_SOCK${OFF}" && return 0
		else
			unset SSH_AUTH_SOCK && debug "Ignoring SSH_AUTH_SOCK -- this is a forwarded socket" && return 1
		fi
	else

		# We have valid SSH_AGENT_PID, so we accept the socket too:
		mesg "Existing ssh-agent ($1): ${CYANN}$SSH_AGENT_PID${OFF}" && return 0
	fi
}

# synopsis: startagent_ssh
# This function specifically handles (potential) starting of ssh-agent. Unlike the
# classic startagent function, it does not handle writing out contents of pidfiles,
# which will be done in a combined way after startagent_gpg() is called as well.

startagent_ssh() {
	if $quickopt; then
		# shellcheck disable=SC2030 # This is fine as sshavail will be called again if needed:
		if ( unset SSH_AGENT_PID SSH_AUTH_SOCK && eval "$(catpidf_shell sh)" && ssh_envcheck pidfile quiet ) && ( sshavail=$(ssh_l) || { [ $? = 1 ] && [ -z "$mykeys" ]; }; ); then
			mesg "Found existing ssh-agent (quick)"
			return 0
		else
			warn "Quick start unsuccessful -- doing regular start..."
		fi
	fi
	takelock || die
	# See if our pidfile is valid without wiping env:
	if ( unset SSH_AGENT_PID SSH_AUTH_SOCK && eval "$(catpidf_shell sh)" && ssh_envcheck pidfile quiet ); then
		# Our pidfile is valid! :) We can simply use it:
		unset SSH_AGENT_PID SSH_AUTH_SOCK && eval "$(catpidf_shell sh)"
	elif $allow_inherited && ssh_envcheck env; then
		# If our env is OK, then let's grab it for our pidfile, as long as we don't have a forwarded ssh connection:
		if [ "$SSH_AGENT_PID" != forwarded ]; then
			pidfile_out="SSH_AUTH_SOCK=\"$SSH_AUTH_SOCK\"; export SSH_AUTH_SOCK"
			if [ -n "$SSH_AGENT_PID" ]; then
				pidfile_out="$pidfile_out
SSH_AGENT_PID=$SSH_AGENT_PID; export SSH_AGENT_PID"
			fi
		fi
	else  # spawn, we must...
		if $ssh_spawn_gpg; then
			startagent_gpg ssh # this function will set pidfile_out itself
			return $?
		else
			mesg "Starting ssh-agent..."
			# shellcheck disable=SC2086 # We purposely don't want to double-quote the args to ssh-agent so they disappear if not used:
			pidfile_out="$(ssh-agent ${ssh_timeout} ${ssh_agent_socket})"
			return $?
		fi
	fi
}

write_pidfile() {
	if [ -n "$pidfile_out" ]; then
		pidfile_out=$(echo "$pidfile_out" | grep -v 'Agent pid')
		case "$pidfile_out" in
			setenv*)
				echo "$pidfile_out" >"$cshpidf"
				echo "$pidfile_out" | awk '{print $2"="$3" export "$2";"}' >"$pidf"
				;;
			*)
				echo "$pidfile_out" >"$pidf"
				echo "$pidfile_out" | sed 's/;.*/;/' | sed 's/=/ /' | sed 's/^/setenv /' >"$cshpidf"
				echo "$pidfile_out" | sed 's/;.*/;/' | sed 's/^\(.*\)=\(.*\);/set -e \1; set -x -U \1 \2;/' >"$fishpidf"
				;;
		esac
	else
		debug skipping creation of pidfiles!
	fi
}

# synopsis: extract_fingerprints
# Extract the fingerprints from standard input, returns space-separated list.
# Utility routine for ssh_l and ssh_f
extract_fingerprints() {
	while read -r ef_line; do
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
		if [ -L "$sf_filename" ] && [ -n "$realpath_bin" ]; then
			sf_filename="$($realpath_bin "$sf_filename")"
		fi
		lsf_filename="$sf_filename.pub"
		if [ ! -f "$lsf_filename" ]; then
			# try to remove extension from private key, *then* add .pub, and see if we now find it:
			if [ -L "$sf_filename" ] && [ -n "$realpath_bin" ]; then
				sf_filename="$($realpath_bin "$sf_filename")"
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
	# shellcheck disable=SC2086
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
	# shellcheck disable=SC2086
	set -- $sshkeys
	IFS="$slm_IFS"	# restore IFS
	set +f			# re-enable globbing

	for slm_k in "$@"; do
		# Fingerprint current user-specified key
		if ! slm_finger=$(ssh_f "$slm_k"); then
			warn "Unable to extract fingerprint from keyfile ${slm_k}.pub, skipping"
			continue
		fi
		slm_wordcount="$(printf -- '%s\n' "$slm_finger" | wc -w)"
		if [ "$slm_wordcount" -ne 1 ]; then
			warn "Unable to extract exactly one key fingerprint from keyfile ${slm_k}.pub, got $slm_wordcount instead, skipping"
			continue
		fi

		# Check if it needs to be added
		# shellcheck disable=SC2031
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

cat_ssh_config_keys() {
	if $sshconfig; then
		if $confallhosts; then
			while IFS= read -r line; do
			case $line in
				*[Ii][Dd][Ee][Nn][Tt][Ii][Tt][Yy][Ff][Ii][Ll][Ee]*)
				echo "$line" | awk '{print $2}'
			esac
			done < ~/.ssh/config
		else
			confpath "$confhost"
		fi
	fi
}

parse_mykeys() {
	while IFS= read -r pm_k; do
		[ -z "$pm_k" ] && continue
		if [ -f "$pm_k" ]; then
			echo "sshk:$pm_k"
		elif [ -f "$HOME/.ssh/$pm_k" ]; then
			echo "sshk:$HOME/.ssh/$pm_k"
		elif [ "$1" != "ssh" ] && "${gpg_prog_name}" --list-secret-keys "$pm_k" >/dev/null 2>&1; then
			echo "gpgk:$pm_k"
		else
			echo "miss:$pm_k"
		fi
	done
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

# synopsis: confpath
# Return private key path if found in ~/.ssh/config SSH configuration file.
# Input: the name of the host we would like to connect to.
confpath() {
	h=""
	while IFS= read -r line; do
		# get the Host directives
		case $line in
			*[Hh][Oo][Ss][Tt]" "*) h=$(echo "$line" | awk '{print $2}') ;;
		esac
		case $line in
			*[Ii][Dd][Ee][Nn][Tt][Ii][Tt][Yy][Ff][Ii][Ll][Ee]*)
			if [ "$h" = "$1" ]; then
				echo "$line" | awk '{print $2}'
				break
			fi
		esac
	done < ~/.ssh/config
}

wantagent() {
	[ "$1" = "gpg" ] && [ -n "$gpgkeys" ] && return 0
	[ "$1" = "ssh" ] && return 0
	return 1
}

gpg_wipe() {
	out="$( echo RELOADAGENT | gpg-connect-agent --no-autostart 2>/dev/null )"
	if [ "$out" = "OK" ]; then
		mesg "gpg-agent: All identities removed."
	else
		mesg "gpg-agent: Could not remove identities ($out)"
	fi
}

ssh_wipe() {
	if sshout=$(ssh-add -D 2>&1); then
		mesg "ssh-agent: $sshout"
	else
		warn "ssh-agent: $sshout"
	fi

}

#
# MAIN PROGRAM
#

while [ -n "$1" ]; do
	case "$1" in
		--absolute) absoluteopt=true ;;
		--agents) warn "--agents is deprecated, ignoring." ;;
		--agent-socket) shift; ssh_agent_socket="-a $1" ;;
		--confirm) confirmopt=true ;;
		--debug|-D) debugopt=true ;;
		--eval) evalopt=true ;;
		--gpg2) gpg_prog_name="gpg2" ;;
		--gpg-wipe) setaction gpg_wipe ;;
		--help|-h) setaction help ;;
		--host) shift; hostopt="$1" ;;
		--ignore-missing) ignoreopt=true ;;
		--inherit) shift; warn "--inherit is deprecated, ignoring. Use --ssh-allow-forwarded, --noinherit as needed instead.";;
		--list|-l) setaction list ;;
		--list-fp|-L) setaction list-fp ;;
		--noask) noaskopt=true ;;
		--nocolor) color=false ;;
		--nogui) noguiopt=true ;;
		--noinherit) allow_inherited=false ;;
		--nolock) nolockopt=true ;;
		--query) setaction query; quietopt=true ;;
		--quiet|-q) quietopt=true ;;
		--ssh-allow-gpg) ssh_allow_gpg=true ;;
		--ssh-spawn-gpg) ssh_spawn_gpg=true; ssh_allow_gpg=true ;;
		--ssh-agent-socket) shift; ssh_agent_socket="-a $1" ;;
		--ssh-allow-forwarded) ssh_allow_forwarded=true ;;
		--ssh-rm|-r) setaction ssh_rm ;;
		--ssh-wipe) setaction ssh_wipe ;;
		--systemd) systemdopt=true ;;
		--version|-V) setaction version ;;
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
		--confallhosts|-C)
			if [ -e ~/.ssh/config ]; then
				sshconfig=true
				confallhosts=true
			else
				# shellcheck disable=SC2088
				warn "~/.ssh/config not found; --confallhosts/-C option ignored."
			fi
			;;
		--confhost|-c)
			if [ -e ~/.ssh/config ]; then
				sshconfig=true
				confhost="$2"
			else
				# shellcheck disable=SC2088
				warn "~/.ssh/config not found; --confhost/-c option ignored."
			fi
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
		--stop|-k)
			setaction stop
			case $2 in
				all|mine|others) stopwhich="$2" ;;
				*) die "Please specify 'all', 'mine' or 'others' for --stop" ;;
			esac
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

if [ -z "$hostopt" ]; then
	if [ -z "$HOSTNAME" ]; then
		hostopt=$(uname -n 2>/dev/null || echo unknown)
	else
		hostopt="$HOSTNAME"
	fi
fi

pidf="${keydir}/${hostopt}-sh"
cshpidf="${keydir}/${hostopt}-csh"
fishpidf="${keydir}/${hostopt}-fish"
lockf="${keydir}/${hostopt}-lockf"

# Read the env snippet (especially for things like PATH, but could modify basically anything)
if [ -z "$envf" ]; then
	envf="${keydir}/${hostopt}-env"
	[ -f "$envf" ] || envf="${keydir}/env"
	[ -f "$envf" ] || unset envf
fi
if [ -n "$envf" ]; then
	# shellcheck disable=SC1090
	. "$envf"
fi

# Don't use color if there's no terminal on stderr
if [ -n "$OFF" ]; then
	tty <&2 >/dev/null 2>&1 || color=false
fi

#disable color if necessary, right before our initial newline

$color || unset BLUE CYAN CYANN GREEN PURP OFF RED

# TODO: we can't assume pidfile has been created yet? Or not a big deal?
[ "$myaction" = list ] && eval "$(catpidf_shell sh)" && exec ssh-add -l
[ "$myaction" = list-fp ] && eval "$(catpidf_shell sh)" && exec ssh-add -L

qprint #initial newline
mesg "${PURP}keychain ${OFF}${CYANN}${version}${OFF} ~ ${GREEN}http://www.funtoo.org/Funtoo:Keychain${OFF}"

[ "$myaction" = version ] && { versinfo; exit 0; }
[ "$myaction" = help ] && { versinfo; helpinfo; exit 0; }

# Set up traps
# Don't use signal names because they don't work on Cygwin.
if $clearopt; then
	trap '' 2	# disallow ^C until we've had a chance to --clear
	trap 'droplock; exit 1' 1 15	# drop the lock on signal
	trap 'droplock;' 0		# drop the lock on exit
else
	# Don't use signal names because they don't work on Cygwin.
	trap 'droplock; exit 1' 1 2 15	# drop the lock on signal
	trap 'droplock;' 0		# drop the lock on exit
fi

testssh							# sets $openssh, $sunssh and tweaks $ssh_spawn_gpg
verifykeydir					# sets up $keydir
me=$(id -un) || die "Who are you?  id -un doesn't know..."

# --stop: kill the existing ssh-agent(s) (not gpg-agent) and quit
[ "$myaction" = stop ] && stop_ssh_agents

# --timeout translates almost directly to ssh-add/ssh-agent -t, but ssh.com uses
# minutes and OpenSSH uses seconds
if [ -n "$timeout" ]; then
	ssh_timeout=$timeout
	if $openssh || $sunssh; then
		ssh_timeout=$(( ssh_timeout * 60 ))
	fi
	ssh_timeout="-t $ssh_timeout"
fi

# Get keys from SSH configuration files if --confhost/--confallhost are specified, as well as command-line:
all_keys="$(cat_ssh_config_keys | parse_mykeys ssh)$(echo "$mykeys" | parse_mykeys)"
if ! $ignoreopt; then
	for key in $(echo "$all_keys" | grep ^miss:); do
		warn "Can't find key \"${GREEN}$( echo "$key" | cut -c6- )${OFF}\""
	done
fi
sshkeys="$(echo "$all_keys" | sed -n '/^sshk:/s/sshk://p' )"
gpgkeys="$(echo "$all_keys" | sed -n '/^gpgk:/s/gpgk://p' )"

if [ "$myaction" = gpg_wipe ]; then
	gpg_wipe; qprint; exit 0
elif [ "$myaction" = ssh_wipe ]; then
	ssh_wipe; qprint; exit 0
elif [ "$myaction" = query ]; then
	# --query displays current settings, but does not start an agent:
	catpidf_shell sh | cut -d\; -f1 && exit 0
elif [ "$myaction" = ssh_rm ]; then
	if [ -n "$sshkeys" ]; then
		die "No ssh keys specified to remove."
	fi
	for key in $sshkeys; do
		if sshout=$(ssh-add -d "$key" 2>&1); then
			mesg "ssh-agent key $key removed."
		else
			die "keychain was unable to remove ssh-agent key $key. output: $sshout"
		fi
	done
	qprint; exit 0
else
	if ! wantagent ssh && ! wantagent gpg; then
		die "No keys specified. Nothing to do."
	fi
	if wantagent ssh; then
		# This will start gpg-agent as an ssh-agent if such functionality is enabled (default)
		startagent_ssh || warn "Unable to start an ssh-agent (error code: $?)"
	fi
	[ -n "$pidfile_out" ] && write_pidfile && eval "$pidfile_out" > /dev/null
	if ! $gpg_started && wantagent gpg; then
		# If we also want gpg, and it hasn't been started yet, start it also. We don't need to
		# look for pidfile output, as this would have been output from the startagent_ssh->startagent_gpg
		# call above, and gpg doesn't use pidfiles for gpg stuff anymore.
		startagent_gpg || warn "Unable to start gpg-agent (error code: $?)"
	fi
	if $clearopt; then
		if wantagent ssh; then
			ssh_wipe
		fi
		if wantagent gpg; then
			gpg_wipe
		fi
		trap 'droplock' 2 # done clearing, safe to ctrl-c
	fi
fi

if $evalopt; then
	catpidf_shell sh
fi

if $systemdopt; then
	systemctl --user set-environment "$( catpidf_shell sh | cut -d\; -f1 )"
fi

# --noask: "don't ask for keys", so we're all done
$noaskopt && { qprint; exit 0; }
$quickopt && { qprint; exit 0; }

# This is where we load keys as needed:

if wantagent ssh; then
	sshavail=$(ssh_l) # update sshavail now that we're locked
	sshkeys="$(ssh_listmissing)" # cache list of missing keys, newline-separated
	sshattempts=$attempts
	savedisplay="$DISPLAY"

	# Attempt to add the keys
	while [ -n "$sshkeys" ]; do

		# --confirm translates to ssh-add -c
		if $confirmopt; then
			if $openssh || $sunssh; then
				ssh_confirm=-c
			else
				warn "--confirm only works with OpenSSH"
			fi
		fi

		mesg "Adding ${CYANN}$(echo "$sshkeys" | wc -l)${OFF} ssh key(s): $sshkeys"

		# Parse $sshkeys into positional params to preserve spaces in filenames.
		# This *must* happen after any calls to subroutines because pure Bourne
		# shell doesn't restore "$@" following a call.	Eeeeek!
		set -f			# disable globbing
		old_IFS="$IFS"	# save current IFS
		IFS="
"						# set IFS to newline
		# shellcheck disable=SC2086
		set -- $sshkeys
		IFS="$old_IFS"	# restore IFS
		set +f			# re-enable globbing

		if $noguiopt || [ -z "$SSH_ASKPASS" ] || [ -z "$DISPLAY" ]; then
			unset DISPLAY		# DISPLAY="" can cause problems
			unset SSH_ASKPASS	# make sure ssh-add doesn't try SSH_ASKPASS
			
			# shellcheck disable=SC2086 # this is intentional:
			sshout=$(ssh-add ${ssh_timeout} ${ssh_confirm} "$@" 2>&1)
			ret=$?
		else
			# shellcheck disable=SC2086 # this is intentional:
			sshout=$(ssh-add ${ssh_timeout} ${ssh_confirm} "$@" 2>&1 </dev/null)
			ret=$?
		fi
		if [ $ret = 0 ]
		then
			blurb=""
			[ -n "$timeout" ] && blurb="life=${timeout}m"
			[ -n "$timeout" ] && $confirmopt && blurb="${blurb},"
			$confirmopt && blurb="${blurb}confirm"
			[ -n "$blurb" ] && blurb=" (${blurb})"
			mesg "ssh-add: Identities added: $sshkeys${blurb}"
			break
		fi
		if [ "$sshattempts" = 1 ]; then
			die "Problem adding; giving up (error code: $ret; output: $sshout)"
		else
			warn "Problem adding; trying again (error code: $ret; output: $sshout)"
		fi

		# Update the list of missing keys
		sshavail=$(ssh_l) || die "problem running ssh-add -l"
		sshkeys="$(ssh_listmissing)"  # remember, newline-separated

		# Decrement the countdown
		sshattempts=$(( sshattempts -1 ))
	done

	[ -n "$savedisplay" ] && DISPLAY="$savedisplay"
fi

# Load gpg keys
if wantagent gpg; then
	gpgkeys="$(gpg_listmissing)" # cache list of missing keys, newline-separated
	gpgattempts=$attempts

	$noguiopt && unset DISPLAY
	[ -n "$DISPLAY" ] || unset DISPLAY # DISPLAY="" can cause problems
	GPG_TTY=$(tty) ; export GPG_TTY # fall back to ncurses pinentry

	# Attempt to add the keys
	while [ -n "$gpgkeys" ]; do
		tryagain=false

		mesg "Adding ${BLUE} $(echo "$gpgkeys" | wc -l)${OFF} gpg key(s): $gpgkeys"

		# Parse $gpgkeys into positional params to preserve spaces in filenames.
		# This *must* happen after any calls to subroutines because pure Bourne
		# shell doesn't restore "$@" following a call.	Eeeeek!
		set -f			# disable globbing
		old_IFS="$IFS"	# save current IFS
		IFS="
"						# set IFS to newline
		set -- "$gpgkeys"
		IFS="$old_IFS"	# restore IFS
		set +f			# re-enable globbing

		for k in "$@"; do
			gpgout="$(echo | env LC_ALL="$pinentry_lc_all" "${gpg_prog_name}" --no-options --use-agent --no-tty --sign --local-user "$k" -o- 2>&1)"
			ret=$?
			if [ "$ret" -ne 0 ]; then
				tryagain=true
				warn "Error adding gpg key (error code: $ret; output: $gpgout)"
			fi 
		done
		$tryagain || break

		if [ "$gpgattempts" = 1 ]; then
			die "Problem adding (is pinentry installed?); giving up"
		else
			warn "Problem adding; trying again"
		fi

		# Update the list of missing keys
		gpgkeys="$(gpg_listmissing)"  # remember, newline-separated

		# Decrement the countdown
		gpgattempts=$(( gpgattempts - 1 ))
	done
fi

qprint	# trailing newline