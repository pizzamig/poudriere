#!/bin/sh
# 
# Copyright (c) 2013 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

usage() {
	cat << EOF
poudriere status [options]

Options:
    -a          -- Show all builds, not just latest. This implies -f.
    -f          -- Show finished builds as well. This is default
                   if -B or -a are specified.
    -b          -- Display status of each builder for the matched build.
    -B name     -- What buildname to use (must be unique, defaults to
                   "latest"). This implies -f.
    -c          -- Compact output (shorter headers and no logs/url)
    -j name     -- Run on the given jail
    -p tree     -- Specify on which ports tree to match for the build.
    -l          -- Show logs instead of URL.
    -H          -- Script mode. Do not print headers and separate fields by a
                   single tab instead of arbitrary white space.
    -z set      -- Specify which SET to match for the build. Use '0' to only
                   match on empty sets.
EOF
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`

PTNAME=
SETNAME=
SCRIPT_MODE=0
ALL=0
SHOW_FINISHED=0
COMPACT=0
URL=1
BUILDER_INFO=0
BUILDNAME=

. ${SCRIPTPREFIX}/common.sh

while getopts "abB:cfj:lp:Hz:" FLAG; do
	case "${FLAG}" in
		a)
			ALL=1
			SHOW_FINISHED=1
			BUILDNAME_GLOB="*"
			;;
		b)
			BUILDER_INFO=1
			;;
		B)
			BUILDNAME_GLOB="${OPTARG}"
			SHOW_FINISHED=1
			;;
		c)
			COMPACT=1
			;;
		f)
			SHOW_FINISHED=1
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		l)
			URL=0
			;;
		p)
			PTNAME=${OPTARG}
			;;
		H)
			SCRIPT_MODE=1
			;;
		z)
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))

# Default to "latest" if not using -a and no -B specified
[ ${ALL} -eq 0 ] && : ${BUILDNAME_GLOB:=latest}

POUDRIERE_BUILD_TYPE=bulk
now="$(date +%s)"

display=
add_display() {
	if [ ${SCRIPT_MODE} -eq 1 ]; then
		echo "$@"
		return 0
	fi
	if [ -z "${display}" ]; then
		display="$@"
	else
		display="${display}
$@"
	fi
}

if [ ${COMPACT} -eq 0 ]; then
	columns=13
else
	columns=12
fi
if [ ${SCRIPT_MODE} -eq 0 -a ${BUILDER_INFO} -eq 0 ]; then
	format="%%-%ds %%-%ds %%-%ds %%-%ds %%-%ds %%%ds %%%ds %%%ds %%%ds %%%ds %%%ds %%-%ds"
	[ ${COMPACT} -eq 0 ] && format="${format} %%s"
	if [ ${COMPACT} -eq 0 ]; then 
		if [ -n "${URL_BASE}" ] && [ ${URL} -eq 1 ]; then
			url_logs="URL"
		else
			url_logs="LOGS"
		fi
		add_display "SET" "PORTS" "JAIL" "BUILD" "STATUS" "QUEUED" \
		    "BUILT" "FAILED" "SKIPPED" "IGNORED" "TOBUILD" \
		    "TIME" "${url_logs}"
	else
		add_display "SET" "PORTS" "JAIL" "BUILD" "STATUS" "Q" \
		    "B" "F" "S" "I" "R" "TIME"
	fi
else
	format="%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s"
	[ ${COMPACT} -eq 0 ] && format="${format}\t%s"
fi

add_build() {
	local status nbqueued nbfailed nbignored nbskipped nbbuilt nbtobuild
	local elapsed time url builders

	if [ ${BUILDER_INFO} -eq 0 ]; then
		_bget status status 2>/dev/null || :
		_bget nbqueued stats_queued 2>/dev/null || :
		_bget nbbuilt stats_built 2>/dev/null || :
		_bget nbfailed stats_failed 2>/dev/null || :
		_bget nbignored stats_ignored 2>/dev/null || :
		_bget nbskipped stats_skipped 2>/dev/null || :
		nbtobuild=$((nbqueued - (nbbuilt + nbfailed + nbskipped + nbignored)))

		calculate_elapsed ${now} ${log}
		elapsed=${_elapsed_time}
		time=$(date -j -u -r ${elapsed} "+${DURATION_FORMAT}")

		url=
		if [ ${COMPACT} -eq 0 ]; then
			if [ -n "${URL_BASE}" ] && [ ${URL} -eq 1 ]; then
				url="${URL_BASE}/${POUDRIERE_BUILD_TYPE}/${MASTERNAME}/${BUILDNAME}"
			else
				url="${log}"
			fi
		fi
		add_display "${setname:-!}" "${ptname}" "${jailname}" \
		    "${BUILDNAME}" "${status:-?}" "${nbqueued:-?}" \
		    "${nbbuilt:-?}" "${nbfailed:-?}" "${nbskipped:-?}" \
		    "${nbignored:-?}" "${nbtobuild:-?}" "${time:-?}" \
		    "${url}"
	else

		_bget builders builders 2>/dev/null || :

		MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
		JOBS="${builders}" siginfo_handler
	fi
}

found_jobs=0
[ ${SCRIPT_MODE} -eq 0 -a -n "${BUILDNAME_GLOB}" \
    -a "${BUILDNAME_GLOB}" != "latest" ] && \
    msg_warn "Looking up all matching builds. This may take a while."
for mastername in ${POUDRIERE_DATA}/logs/bulk/*; do
	# Check empty dir
	case "${mastername}" in
		"${POUDRIERE_DATA}/logs/bulk/*") break ;;
	esac
	[ -L "${mastername}/latest" ] || continue
	MASTERNAME=${mastername#${POUDRIERE_DATA}/logs/bulk/}
	[ "${MASTERNAME}" = "latest-per-pkg" ] && continue
	[ ${SHOW_FINISHED} -eq 0 ] && ! jail_runs ${MASTERNAME} && continue

	# Look for all wanted buildnames (will be 1 or Many(-a)))
	for buildname in ${mastername}/${BUILDNAME_GLOB}; do
		# Check for no match. If not using a glob ensure the file exists
		# otherwise check for the glob coming back
		if [ "${BUILDNAME_GLOB%\**}" != "${BUILDNAME_GLOB}" ]; then
			case "${buildname}" in
				"${mastername}/${BUILDNAME_GLOB}") break ;;
				# Skip latest if from a glob, let it be found
				# normally.
				"${mastername}/latest") break ;;
				# Don't want latest-per-pkg
				"${mastername}/latest-per-pkg") break ;;
			esac
		else
			# No match
			[ -e "${buildname}" ] || break
		fi
		buildname="${buildname#${mastername}/}"
		BUILDNAME="${buildname}"
		# Unset so later they can be checked for NULL (don't want to
		# lookup again if value looked up is empty
		unset jailname ptname setname
		# Try matching on any given JAILNAME/PTNAME/SETNAME,
		# and if any don't match skip this MASTERNAME entirely.
		if [ -n "${JAILNAME}" ]; then
			_bget jailname jailname 2>/dev/null || :
			[ "${jailname}" = "${JAILNAME}" ] || continue 2
		fi
		if [ -n "${PTNAME}" ]; then
			_bget ptname ptname 2>/dev/null || :
			[ "${ptname}" = "${PTNAME}" ] || continue 2
		fi
		if [ -n "${SETNAME}" ]; then
			_bget setname setname 2>/dev/null || :
			[ "${setname}" = "${SETNAME%0}" ] || continue 2
		fi
		# Dereference latest into actual buildname
		[ "${buildname}" = "latest" ] && \
		    _bget BUILDNAME buildname 2>/dev/null
		# May be blank if build is still starting up
		[ -z "${BUILDNAME}" ] && continue 2

		found_jobs=$((${found_jobs} + 1))

		# Lookup jailname/setname/ptname if needed. Delayed
		# from earlier for performance for -a
		[ -z "${jailname+null}" ] && \
		    _bget jailname jailname 2>/dev/null || :
		[ -z "${setname+null}" ] && \
		    _bget setname setname 2>/dev/null || :
		[ -z "${ptname+null}" ] && \
		    _bget ptname ptname 2>/dev/null || :
		log=${mastername}/${BUILDNAME}

		add_build
	done

done

if [ ${SCRIPT_MODE} -eq 0 -a ${BUILDER_INFO} -eq 0 ]; then
	if [ ${found_jobs} -eq 0 ]; then
		if [ ${SHOW_FINISHED} -eq 0 ]; then
			msg "No running builds. Use -a or -f to show finished builds."
		else
			msg "No matching builds found."
		fi
		exit 0
	fi

	# Determine optimal format
	while read line; do
		cnt=0
		for word in ${line}; do
			hash_get lengths ${cnt} max_length || max_length=0
			if [ ${#word} -gt ${max_length} ]; then
				hash_set lengths ${cnt} ${#word}
			fi
			cnt=$((${cnt} + 1))
		done
	done <<-EOF
	${display}
	EOF

	# Set format lengths
	lengths=
	for n in $(jot $((${columns} - 1)) 0); do
		hash_get lengths ${n} length
		lengths="${lengths} ${length}"
	done
	format=$(printf "${format}" ${lengths})

	# Show header separately so it is not sorted
	echo "${display}"| head -n 1| while read line; do
		printf "${format}\n" ${line}
	done

	# Sort by SET,PTNAME,JAIL,BUILD
	echo "${display}" | tail -n +2 | \
	    sort -d -k1,1V -k2,2 -k3,3 -k4,4n | while read line; do
		# The ! is to hack around empty values.
		printf "${format}\n" ${line} | sed -e 's,!, ,g'
	done

	[ -t 0 ] && \
	    [ -n "${JAILNAME}" -a ${BUILDER_INFO} -eq 0 ] && \
	    msg "Use -b to show detailed builder output."
	msg "Found ${found_jobs} matching builds."
fi
