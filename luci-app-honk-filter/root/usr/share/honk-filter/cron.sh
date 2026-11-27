#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Manages the honk-filter auto-update cron entry. Keeps a single tagged line
# in /etc/crontabs/root so it never collides with user cron entries.

CRON=/etc/crontabs/root
TAG='# honk-filter-auto'
UPDATE=/usr/share/honk-filter/update.sh
LINE="0 3 * * * $UPDATE all >/dev/null 2>&1 $TAG"

case "$1" in
	enable)
		mkdir -p /etc/crontabs 2>/dev/null || exit 1
		[ -f "$CRON" ] || : > "$CRON"
		grep -qF "$TAG" "$CRON" 2>/dev/null || printf '%s\n' "$LINE" >> "$CRON"
		/etc/init.d/cron restart >/dev/null 2>&1 || :
		echo enabled
		;;
	disable)
		[ -f "$CRON" ] || { echo disabled; exit 0; }
		local tmp
		tmp=$(mktemp /etc/crontabs/.hf.XXXXXX) || exit 1
		grep -vF "$TAG" "$CRON" > "$tmp" 2>/dev/null || : > "$tmp"
		mv -f "$tmp" "$CRON"
		/etc/init.d/cron restart >/dev/null 2>&1 || :
		echo disabled
		;;
	status)
		if grep -qF "$TAG" "$CRON" 2>/dev/null; then echo enabled; else echo disabled; fi
		;;
	*)
		echo "usage: $0 {enable|disable|status}" >&2
		exit 2
		;;
esac
