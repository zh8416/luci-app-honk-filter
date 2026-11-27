#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Honk filter rule source updater.
# Downloads online rule sources into the source dir, then triggers a rebuild.
# Download failures never destroy previously downloaded rules.

set -f

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

hex_bytes() {
	# BusyBox-safe byte count without wc -c on possibly binary data.
	wc -c < "$1" 2>/dev/null | tr -d ' '
}

fetch_one() {
	local section=$1 name url format ua tmp dest old_hash new_hash bytes
	config_get name "$section" name "$section"
	config_get url "$section" url ''
	config_get format "$section" format auto
	config_get ua "$section" ua "$USER_AGENT"

	[ -n "$url" ] || return 1
	case "$url" in
		http://*|https://*) ;;
		*) logline "source '$name': unsupported url scheme"; return 1 ;;
	esac

	dest="$SOURCE_DIR/$section.txt"
	tmp=$(mktemp "$SOURCE_DIR/.fetch.XXXXXX") || return 1

	if ! wget -q --no-check-certificate -U "$ua" -T 30 -O "$tmp" "$url" 2>>"$LOG_FILE"; then
		logline "source '$name': download failed"
		rm -f "$tmp"
		return 1
	fi

	bytes=$(hex_bytes "$tmp")
	case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
	if [ "$bytes" -lt 32 ] || [ "$bytes" -gt "$MAX_BYTES" ]; then
		logline "source '$name': bad size ($bytes)"
		rm -f "$tmp"
		return 1
	fi

	# Hash-based change detection: skip rebuild-triggering copy if identical.
	new_hash=$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')
	old_hash=
	[ -f "$dest" ] && old_hash=$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')

	if [ "$new_hash" = "$old_hash" ] && [ -n "$old_hash" ]; then
		cp -f "$tmp" "$dest" 2>/dev/null
		rm -f "$tmp"
		logline "source '$name': unchanged ($bytes bytes)"
		return 0
	fi

	mv -f "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
	uci -q set "honk-filter.$section.last_update=$(date +%s)"
	uci -q set "honk-filter.$section.fail_count=0"
	logline "source '$name': updated ($bytes bytes)"
	return 0
}

update_all() {
	local only=$1 rc=0
	mkdir -p "$SOURCE_DIR" 2>/dev/null || exit 1
	config_load honk-filter
	if [ -n "$only" ]; then
		local enabled
		config_get enabled "$only" enabled 0
		[ "$enabled" = 1 ] || { logline "source '$only': disabled"; exit 1; }
		fetch_one "$only" || rc=1
	else
		config_foreach _update_cb source
	fi
	uci -q commit honk-filter 2>/dev/null || :
	FILTER_REBUILD_QUIET=1 "$FILTER" rebuild >/dev/null 2>&1 || rc=1
	return $rc
}

_update_cb() {
	local section=$1 enabled
	config_get enabled "$section" enabled 0
	[ "$enabled" = 1 ] || return 0
	fetch_one "$section" || {
		local name fail
		config_get name "$section" name "$section"
		config_get fail "$section" fail_count 0
		fail=$((fail + 1))
		uci -q set "honk-filter.$section.fail_count=$fail"
	}
}

case "$1" in
	all) update_all ;;
	one) shift; update_all "$1" ;;
	*) echo "usage: $0 {all|one <section>}" >&2; exit 2 ;;
esac
