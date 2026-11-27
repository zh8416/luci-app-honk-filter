#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Honk filter rule source updater.
# Downloads online rule sources into the source dir, then triggers a rebuild.
# Download failures never destroy previously downloaded rules.
#
# Output: a JSON summary on stdout so the LuCI backend can show real results.

. /usr/share/libubox/jshn.sh 2>/dev/null
. /lib/functions.sh 2>/dev/null

FILTER=/usr/share/honk-filter/filter.sh
STATE_DIR=/etc/honk/filter
SOURCE_DIR=$STATE_DIR/sources
LOG_FILE=/tmp/honk-filter.log
USER_AGENT='Mozilla/5.0 (X11; Linux x86_64) honk-filter/1.0'
MAX_BYTES=$((8 * 1024 * 1024))

logline() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || :
	logger -t honk-filter "$*" 2>/dev/null || :
}

byte_count() {
	wc -c < "$1" 2>/dev/null | tr -d ' '
}

# uci -q get works for both named sections and anonymous @source[N] handles;
# config_get() does not accept @source[N]. Use this everywhere.
get_opt() {
	local val
	val=$(uci -q get "honk-filter.$1.$2" 2>/dev/null)
	[ -n "$val" ] && printf '%s' "$val" || printf '%s' "$3"
}

# Fetch URL into $2. Prefer curl with HTTP/1.1 + IPv4 (avoids the TLS
# "unexpected eof while reading" seen with BusyBox wget / TLS 1.3 keepalive on
# OpenWrt), fall back to wget. Never follow redirects through IPv6.
download_to() {
	local url=$1 out=$2 ua=$3
	rm -f "$out" 2>/dev/null
	if command -v curl >/dev/null 2>&1; then
		if curl -4 -fsSL --http1.1 -k --connect-timeout 10 --max-time 30 \
			-A "$ua" -o "$out" "$url" 2>>"$LOG_FILE"; then
			return 0
		fi
		rm -f "$out" 2>/dev/null
	fi
	wget -4 -q --no-check-certificate -U "$ua" -T 30 -O "$out" "$url" 2>>"$LOG_FILE"
}

fetch_one() {
	local section=$1 name url format ua tmp dest old_hash new_hash bytes reason
	name=$(get_opt "$section" name "$section")
	url=$(get_opt "$section" url '')
	format=$(get_opt "$section" format auto)
	ua=$(get_opt "$section" ua "$USER_AGENT")

	[ -n "$url" ] || { printf 'invalid_url'; return 1; }
	case "$url" in
		http://*|https://*) ;;
		*) printf 'unsupported_scheme'; return 1 ;;
	esac

	mkdir -p "$SOURCE_DIR" 2>/dev/null || { printf 'state_dir_error'; return 1; }
	dest="$SOURCE_DIR/$section.txt"
	tmp="$SOURCE_DIR/.fetch.$section.$$"

	if ! download_to "$url" "$tmp" "$ua"; then
		logline "source '$name': download failed"
		rm -f "$tmp" 2>/dev/null
		printf 'download_failed'
		return 1
	fi

	bytes=$(byte_count "$tmp")
	case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
	if [ "$bytes" -lt 32 ] || [ "$bytes" -gt "$MAX_BYTES" ]; then
		logline "source '$name': bad size ($bytes)"
		rm -f "$tmp" 2>/dev/null
		printf 'bad_size:%s' "$bytes"
		return 1
	fi

	new_hash=$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')
	old_hash=
	[ -f "$dest" ] && old_hash=$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')

	if [ "$new_hash" = "$old_hash" ] && [ -n "$old_hash" ]; then
		cp -f "$tmp" "$dest" 2>/dev/null
		rm -f "$tmp" 2>/dev/null
		logline "source '$name': unchanged ($bytes bytes)"
		printf 'unchanged:%s' "$bytes"
		return 0
	fi

	mv -f "$tmp" "$dest" || { rm -f "$tmp" 2>/dev/null; printf 'move_failed'; return 1; }
	uci -q set "honk-filter.$section.last_update=$(date +%s)"
	uci -q set "honk-filter.$section.fail_count=0"
	logline "source '$name': updated ($bytes bytes)"
	printf 'updated:%s' "$bytes"
	return 0
}

emit_summary() {
	local ok=$1 updated=$2 failed=$3 details=$4
	[ "$ok" = true ] && ok=1 || ok=0
	json_init
	json_add_boolean ok "$ok"
	json_add_int updated "$updated"
	json_add_int failed "$failed"
	json_add_string details "$details"
	json_dump
}

update_all() {
	local only=$1 updated=0 failed=0 details='' rebuild_rc=0 reason name
	mkdir -p "$SOURCE_DIR" 2>/dev/null || exit 1
	config_load honk-filter
	if [ -n "$only" ]; then
		local enabled
		enabled=$(get_opt "$only" enabled 0)
		if [ "$enabled" != 1 ]; then
			emit_summary false 0 1 "disabled"
			exit 1
		fi
		name=$(get_opt "$only" name "$only")
		reason=$(fetch_one "$only")
		local fetch_rc=$?
		if [ "$fetch_rc" -eq 0 ]; then updated=1; else failed=1; fi
		details="$name: $reason"
	else
		config_foreach _update_cb source
		updated=$UPDATED_COUNT
		failed=$FAILED_COUNT
		details=$DETAILS
	fi
	uci -q commit honk-filter 2>/dev/null || :

	FILTER_REBUILD_QUIET=1 "$FILTER" rebuild >/dev/null 2>&1 || rebuild_rc=1
	if [ "$failed" -gt 0 ] || [ "$rebuild_rc" -ne 0 ]; then
		emit_summary false "$updated" "$failed" "$details"
		return 1
	fi
	emit_summary true "$updated" "$failed" "$details"
	return 0
}

UPDATED_COUNT=0
FAILED_COUNT=0
DETAILS=''

_update_cb() {
	local section=$1 enabled name reason
	enabled=$(get_opt "$section" enabled 0)
	[ "$enabled" = 1 ] || return 0
	name=$(get_opt "$section" name "$section")
	reason=$(fetch_one "$section")
	if [ $? -eq 0 ]; then
		UPDATED_COUNT=$((UPDATED_COUNT + 1))
	else
		FAILED_COUNT=$((FAILED_COUNT + 1))
		local fail
		fail=$(get_opt "$section" fail_count 0)
		fail=$((fail + 1))
		uci -q set "honk-filter.$section.fail_count=$fail"
	fi
	[ -n "$DETAILS" ] && DETAILS="$DETAILS; "
	DETAILS="${DETAILS}${name}: ${reason}"
}

case "$1" in
	all) update_all ;;
	one) shift; update_all "$1" ;;
	*) echo '{"ok":false,"updated":0,"failed":0,"details":"usage"}' >&2; exit 2 ;;
esac
