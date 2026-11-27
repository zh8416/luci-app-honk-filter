#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Honk native filter engine — parses rule sources into Honk block rules.
#
# Design rules (respect target environment):
#   * BusyBox only: no base64/xxd/od, no grep -P, no xargs -P, no sort -h.
#   * All writes are validate-then-promote with automatic rollback.
#   * Rules are written into config.dae inside a managed marker block, so the
#     existing config_owner() layout detection (file system unknown) is intact.
#   * Never touch /etc/honk/config.dae directly: build a candidate, validate,
#     promote, reload; on failure restore the previous file.
#
# Usage:
#   filter.sh rebuild            # rebuild adblock rules from all enabled sources
#   filter.sh enable             # ensure marker block present + rebuild
#   filter.sh disable            # remove rules from marker block
#   filter.sh sources            # print JSON array of configured sources
#   filter.sh stats              # print JSON stats about current rules
#   filter.sh whitelist-add <domain>
#   filter.sh whitelist-remove <domain>
#   filter.sh custom-add <domain>
#   filter.sh custom-remove <domain>

set -f

. /usr/share/libubox/jshn.sh 2>/dev/null
. /lib/functions.sh 2>/dev/null
. /usr/share/honk/lifecycle.sh 2>/dev/null

CORE=/usr/bin/honk-core
CFG=/etc/honk/config.dae
STATE_DIR=/etc/honk/filter
RULE_FILE=$STATE_DIR/ads.dae
WHITELIST_FILE=$STATE_DIR/whitelist.txt
CUSTOM_FILE=$STATE_DIR/custom.txt
SOURCE_DIR=$STATE_DIR/sources
LOG_FILE=/tmp/honk-filter.log
BEGIN_MARK='    # honk-filter:adblock-begin'
END_MARK='    # honk-filter:adblock-end'
MAX_RULES=200000

msg() { logger -t honk-filter "$*" 2>/dev/null || :; }

logline() {
	local line
	line=$(date '+%Y-%m-%d %H:%M:%S')" $*"
	printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || :
	[ "$(wc -l < "$LOG_FILE" 2>/dev/null)" -le 500 ] || \
		tail -n 200 "$LOG_FILE" > "$LOG_FILE.1" 2>/dev/null && mv -f "$LOG_FILE.1" "$LOG_FILE" 2>/dev/null
	msg "$*"
}

ensure_state() {
	mkdir -p "$STATE_DIR" "$SOURCE_DIR" 2>/dev/null || return 1
	[ -f "$WHITELIST_FILE" ] || : > "$WHITELIST_FILE"
	[ -f "$CUSTOM_FILE" ] || : > "$CUSTOM_FILE"
	return 0
}

# ---------- rule parsing ----------
# Reads a rule file on stdin, writes normalized domain list on stdout.
# Supported: pure domain, hosts (0.0.0.0 / 127.0.0.1), ABP ||domain^,
#            @@domain (whitelist -> prefixed with !).
parse_rules() {
	awk '
		function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
		{
			line = $0
			sub(/\r$/, "", line)
			line = trim(line)
			if (line == "") next
			if (line ~ /^!/) next
			if (line ~ /^#/) next
			sub(/[[:space:]]*#.*$/, "", line)
			line = trim(line)
			if (line == "") next

			dom = ""

			# @@ whitelist marker
			if (line ~ /^@@/) {
				rest = substr(line, 3)
				if (match(rest, /[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}/)) {
					dom = "!" substr(rest, RSTART, RLENGTH)
				}
			}
			# ABP ||domain^
			else if (line ~ /^\|\|/) {
				rest = substr(line, 3)
				if (match(rest, /[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}/)) {
					dom = substr(rest, RSTART, RLENGTH)
				}
			}
			# hosts: 0.0.0.0 domain / 127.0.0.1 domain
			else if (line ~ /^(0\.0\.0\.0|127\.0\.0\.1|::)/) {
				n = split(line, f, /[[:space:]]+/)
				for (i = 2; i <= n; i++) {
					if (f[i] ~ /^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$/) { dom = f[i]; break }
				}
			}
			# ABP markers / regex rules -> skip
			else if (line ~ /^[\/\[]/ || line ~ /\$/ || line ~ /\*/) {
				next
			}
			# pure domain
			else if (line ~ /^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$/) {
				dom = line
			}

			if (dom == "") next
			dom = tolower(dom)
			sub(/^\.+/, "", dom)
			sub(/\.+$/, "", dom)
			if (dom == "") next
			print dom
		}
	' | sort -u
}

# Build the aggregated rule list from all enabled sources + custom + whitelist.
build_domain_list() {
	ensure_state || return 1
	local tmp
	tmp=$(mktemp "$STATE_DIR/.domains.XXXXXX") || return 1
	: > "$tmp"

	local f
	for f in "$SOURCE_DIR"/*.txt; do
		[ -f "$f" ] || continue
		parse_rules < "$f" >> "$tmp"
	done
	[ -f "$CUSTOM_FILE" ] && parse_rules < "$CUSTOM_FILE" >> "$tmp"

	# Apply whitelist: remove exact matches and !-marked entries
	local wl="$STATE_DIR/.wl.$$"
	{
		awk '{ print tolower($0) }' "$WHITELIST_FILE" 2>/dev/null
		awk '/^!/ { print tolower(substr($0,2)) }' "$tmp" 2>/dev/null
	} | sed '/^$/d' | sort -u > "$wl"

	awk -v wl="$wl" '
		BEGIN { while ((getline w < wl) > 0) ex[w] = 1; close(wl) }
		{
			if ($0 ~ /^!/) next
			if ($0 in ex) next
			print
		}
	' "$tmp" | sort -u > "$tmp.sorted"

	mv -f "$tmp.sorted" "$tmp"
	rm -f "$wl"
	cat "$tmp"
	rm -f "$tmp"
}

# Convert a domain list (stdin) into a honk block rule file.
gen_dae_block() {
	awk '
		BEGIN {
			print "    # honk-filter: generated block rules"
			print "    domain("
			first = 1
			n = 0
		}
		{
			if ($0 == "" || $0 ~ /^!/) next
			if (n >= 200000) next
			if (first) { printf "        %s", $0; first = 0 }
			else { printf ",\n        %s", $0 }
			n++
		}
		END {
			if (!first) printf "\n"
			print "    ) -> block"
		}
	'
}

# ---------- config marker block manipulation ----------
# Replace content between begin/end marks. If marks are missing, insert a new
# managed block at the top of the existing top-level routing{} block, so block
# rules take precedence over `domain(geosite: cn) -> direct`.
# Two explicit passes (grep first) avoid the streaming pitfall where a
# `routing {` line is seen before an existing begin mark further down.
render_config() {
	local rules_file=$1
	local out=$2
	if config_has_marks; then
		# Replace mode: only swap the content between the two marks.
		awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v rf="$rules_file" '
			function emit_rules() { while ((getline r < rf) > 0) print r; close(rf) }
			BEGIN { inblock = 0 }
			{
				line = $0
				if (!inblock && line == begin) { inblock = 1; print line; emit_rules(); next }
				if (inblock && line == end) { inblock = 0; print line; next }
				if (inblock) next
				print line
			}
		' "$CFG" > "$out"
	else
		# Insert mode: no marks exist, add one managed block at top of routing{}.
		awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v rf="$rules_file" '
			function emit_rules() { while ((getline r < rf) > 0) print r; close(rf) }
			BEGIN { inserted = 0 }
			{
				line = $0
				# Top-level `routing {` has no leading whitespace (dns.routing is indented).
				if (!inserted && line ~ /^routing[[:space:]]*\{/) {
					print line; print begin; emit_rules(); print end; inserted = 1; next
				}
				print line
			}
			END {
				if (!inserted) {
					print ""; print "routing {"; print begin; emit_rules(); print end; print "}"
				}
			}
		' "$CFG" > "$out"
	fi
}

config_has_marks() {
	grep -qF "$BEGIN_MARK" "$CFG" 2>/dev/null && grep -qF "$END_MARK" "$CFG" 2>/dev/null
}

validate_candidate() {
	local cand=$1
	[ -x "$CORE" ] || return 2
	"$CORE" config validate --config "$cand" >/dev/null 2>&1
}

apply_candidate() {
	local cand=$1
	local backup
	backup=$(mktemp /etc/honk/.filter-backup.XXXXXX) || return 1
	cp -p "$CFG" "$backup" || { rm -f "$backup"; return 1; }
	cp "$cand" "$CFG" || { cp -p "$backup" "$CFG"; rm -f "$backup"; return 1; }
	/etc/init.d/honk reload >/dev/null 2>&1
	local rc=$?
	if [ "$rc" -ne 0 ]; then
		cp -p "$backup" "$CFG" 2>/dev/null
		/etc/init.d/honk reload >/dev/null 2>&1 || :
		rm -f "$backup"
		return 1
	fi
	rm -f "$backup"
	return 0
}

# ---------- DNS routing ----------
# Rewrite only specific field lines inside config.dae, preserving all other
# user configuration. Each field is matched by its exact leading token.
dns_apply() {
	local defup remup boot fallback cache ipv6
	defup=$(uci -q get honk-filter.dns.default_upstream)
	remup=$(uci -q get honk-filter.dns.remote_upstream)
	boot=$(uci -q get honk-filter.dns.bootstrap)
	fallback=$(uci -q get honk-filter.dns.fallback)
	cache=$(uci -q get honk-filter.dns.cache 2>/dev/null); [ -n "$cache" ] || cache=1
	ipv6=$(uci -q get honk-filter.dns.ipv6 2>/dev/null); [ -n "$ipv6" ] || ipv6=1
	[ -n "$defup" ] || defup='https://223.5.5.5/dns-query?tls_server_name=dns.alidns.com'
	[ -n "$remup" ] || remup='https://8.8.8.8/dns-query?tls_server_name=dns.google'
	[ -n "$boot" ] || boot='1.1.1.1:53'
	case "$fallback" in remote|default|accept) ;; *) fallback=remote ;; esac

	local cand
	cand=$(mktemp /etc/honk/.dns-cand.XXXXXX) || return 1
	awk \
		-v defup="$defup" -v remup="$remup" -v boot="$boot" \
		-v fallback="$fallback" -v cache="$cache" -v ipv6="$ipv6" '
		{
			line = $0
			# global.bootstrap_resolver
			if (line ~ /^[[:space:]]*bootstrap_resolver:[[:space:]]*/) {
				match(line, /^[[:space:]]*/)
				indent = substr(line, 1, RLENGTH)
				line = indent "bootstrap_resolver: '\''" boot "'\''"
			}
			# dns.upstream default / remote (only the ->direct / ->proxy lines)
			else if (line ~ /^[[:space:]]*default:[[:space:]]*.*->[[:space:]]*direct/) {
				match(line, /^[[:space:]]*/); indent = substr(line, 1, RLENGTH)
				line = indent "default: '\''" defup "'\'' -> direct"
			}
			else if (line ~ /^[[:space:]]*remote:[[:space:]]*.*->[[:space:]]*proxy/) {
				match(line, /^[[:space:]]*/); indent = substr(line, 1, RLENGTH)
				line = indent "remote: '\''" remup "'\'' -> proxy"
			}
			# dns.routing.request.fallback (first fallback: remote inside dns block)
			else if (!fb_done && line ~ /^[[:space:]]*fallback:[[:space:]]*remote[[:space:]]*$/) {
				match(line, /^[[:space:]]*/); indent = substr(line, 1, RLENGTH)
				line = indent "fallback: " fallback
				fb_done = 1
			}
			# experimental.cache_file.enabled
			else if (line ~ /^[[:space:]]*cache_file[[:space:]]*\{/) { in_cache = 1 }
			else if (in_cache && line ~ /^[[:space:]]*\}/) { in_cache = 0 }
			else if (in_cache && line ~ /^[[:space:]]*enabled:[[:space:]]*(true|false)/) {
				match(line, /^[[:space:]]*/); indent = substr(line, 1, RLENGTH)
				line = indent "enabled: " (cache == 1 ? "true" : "false")
			}
			# AAAA: add a response rule flag marker comment for future core support.
			# For now IPv6 is controlled at the resolver level; keep a documented marker.
			print line
		}
	' "$CFG" > "$cand" || { rm -f "$cand"; return 1; }

	if ! validate_candidate "$cand"; then
		logline "dns_apply: validate failed, keeping old config"
		rm -f "$cand"
		return 1
	fi
	if ! apply_candidate "$cand"; then
		logline "dns_apply: reload failed, rolled back"
		rm -f "$cand"
		return 1
	fi
	rm -f "$cand"
	logline "dns_apply: ok"
	return 0
}

# ---------- public operations ----------
do_rebuild() {
	ensure_state || { logline "rebuild: state dir error"; return 1; }
	local domains rules cand
	domains=$(build_domain_list) || { logline "rebuild: build list failed"; return 1; }
	rules=$(mktemp "$STATE_DIR/.rules.XXXXXX") || return 1
	printf '%s\n' "$domains" | gen_dae_block > "$rules"
	local count
	count=$(printf '%s\n' "$domains" | grep -c . 2>/dev/null)
	[ "$count" -le "$MAX_RULES" ] || { logline "rebuild: too many rules ($count)"; rm -f "$rules"; return 1; }

	cand=$(mktemp /etc/honk/.filter-cand.XXXXXX) || { rm -f "$rules"; return 1; }
	render_config "$rules" "$cand" || { rm -f "$rules" "$cand"; return 1; }
	if ! validate_candidate "$cand"; then
		logline "rebuild: validate failed, keeping old rules"
		rm -f "$rules" "$cand"
		return 1
	fi
	if ! apply_candidate "$cand"; then
		logline "rebuild: reload failed, rolled back"
		rm -f "$rules" "$cand"
		return 1
	fi
	cp "$rules" "$RULE_FILE" 2>/dev/null
	printf '%s\n' "$count" > "$STATE_DIR/rule_count" 2>/dev/null
	date +%s > "$STATE_DIR/last_update" 2>/dev/null
	rm -f "$rules" "$cand"
	logline "rebuild: ok, $count domains"
	echo "$count"
}

do_enable() {
	local cand
	uci -q set honk-filter.main.enabled=1 && uci -q commit honk-filter
	do_rebuild
}

do_disable() {
	uci -q set honk-filter.main.enabled=0 && uci -q commit honk-filter
	ensure_state || return 1
	local cand empty
	empty=$(mktemp "$STATE_DIR/.empty.XXXXXX") || return 1
	: > "$empty"
	cand=$(mktemp /etc/honk/.filter-cand.XXXXXX) || { rm -f "$empty"; return 1; }
	render_config "$empty" "$cand" || { rm -f "$empty" "$cand"; return 1; }
	if validate_candidate "$cand" && apply_candidate "$cand"; then
		printf '0\n' > "$STATE_DIR/rule_count" 2>/dev/null
		logline "disabled"
		rm -f "$empty" "$cand"
		return 0
	fi
	rm -f "$empty" "$cand"
	logline "disable: failed"
	return 1
}

do_stats() {
	ensure_state || return 1
	local count ts enabled
	count=$(cat "$STATE_DIR/rule_count" 2>/dev/null)
	case "$count" in ''|*[!0-9]*) count=0 ;; esac
	ts=$(cat "$STATE_DIR/last_update" 2>/dev/null)
	case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
	enabled=$(uci -q get honk-filter.main.enabled 2>/dev/null)
	[ "$enabled" = 1 ] && enabled=true || enabled=false
	json_init
	json_add_boolean enabled "$enabled"
	json_add_int rules "$count"
	json_add_int last_update "$ts"
	json_add_string rule_file "$RULE_FILE"
	json_dump
}

do_sources() {
	ensure_state || return 1
	json_init
	json_add_array sources
	config_load honk-filter
	config_foreach _emit_source source
	json_close_array
	json_dump
}

_emit_source() {
	local section=$1 name url format enabled interval ua last_update fail_count
	config_get name "$section" name ''
	config_get url "$section" url ''
	config_get format "$section" format auto
	config_get enabled "$section" enabled 1
	config_get interval "$section" interval 86400
	config_get ua "$section" ua ''
	config_get last_update "$section" last_update 0
	config_get fail_count "$section" fail_count 0
	json_add_object
	json_add_string section "$section"
	json_add_string name "$name"
	json_add_string url "$url"
	json_add_string format "$format"
	json_add_boolean enabled "$enabled"
	json_add_int interval "$interval"
	json_add_string ua "$ua"
	json_add_int last_update "$last_update"
	json_add_int fail_count "$fail_count"
	json_close_object
}

do_logs() {
	json_init
	json_add_string logs "$(cat "$LOG_FILE" 2>/dev/null)"
	json_dump
}

add_to_file() {
	local file=$1 value=$2
	[ -n "$value" ] || return 1
	case "$value" in *[!A-Za-z0-9.-]*) return 1 ;; esac
	value=$(printf '%s' "$value" | tr 'A-Z' 'a-z')
	grep -qxF "$value" "$file" 2>/dev/null || printf '%s\n' "$value" >> "$file"
	return 0
}

remove_from_file() {
	local file=$1 value=$2
	[ -f "$file" ] || return 0
	value=$(printf '%s' "$value" | tr 'A-Z' 'a-z')
	local tmp
	tmp=$(mktemp "$STATE_DIR/.rm.XXXXXX") || return 1
	grep -vxF "$value" "$file" > "$tmp" 2>/dev/null || : > "$tmp"
	mv -f "$tmp" "$file"
	return 0
}

case "$1" in
	rebuild) do_rebuild ;;
	enable) do_enable ;;
	disable) do_disable ;;
	dns-apply) dns_apply ;;
	stats) do_stats ;;
	sources) do_sources ;;
	logs) do_logs ;;
	whitelist-add) ensure_state && add_to_file "$WHITELIST_FILE" "$2" && do_rebuild >/dev/null ;;
	whitelist-remove) ensure_state && remove_from_file "$WHITELIST_FILE" "$2" && do_rebuild >/dev/null ;;
	custom-add) ensure_state && add_to_file "$CUSTOM_FILE" "$2" && do_rebuild >/dev/null ;;
	custom-remove) ensure_state && remove_from_file "$CUSTOM_FILE" "$2" && do_rebuild >/dev/null ;;
	*)
		echo "usage: $0 {rebuild|enable|disable|dns-apply|stats|sources|logs|whitelist-add|whitelist-remove|custom-add|custom-remove}" >&2
		exit 2
		;;
esac
