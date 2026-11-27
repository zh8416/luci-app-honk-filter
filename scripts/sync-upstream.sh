#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Sync this fork with upstream kenzok8/openwrt-honk, then run compatibility
# checks against the runtime interfaces that luci-app-honk-filter relies on.
#
# All filter code lives in luci-app-honk-filter/ (a brand new directory), so a
# normal upstream merge/rebase should never conflict. This script verifies the
# few *runtime* assumptions instead:
#   1. config.dae still has `dns { upstream { default:/remote: } }` lines
#   2. config.dae still has a top-level routing{} block for the marker block
#   3. /etc/init.d/honk still exists (reload path) — checked by name in source
#   4. lifecycle.sh still exports config_owner/config_include helpers
#
# Usage:
#   scripts/sync-upstream.sh            # fetch + show status, no changes
#   scripts/sync-upstream.sh --apply    # merge upstream/main into main, rebase branch

set -e
cd "$(dirname "$0")/.."

UPSTREAM=${UPSTREAM:-upstream}
BASE=main
BRANCH=filter-v1

GITENV="env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy git -c http.sslBackend=openssl -c http.version=HTTP/1.1"

echo "==> fetching upstream"
$GITENV fetch "$UPSTREAM" || { echo "fetch failed; check network/proxy"; exit 1; }

echo "==> upstream head: $($GITENV log "$UPSTREAM/$BASE" -1 --format='%h %s')"
echo "==> local main:    $($GITENV log "$BASE" -1 --format='%h %s')"

if [ "$1" = "--apply" ]; then
	echo "==> merging upstream into $BASE"
	$GITENV checkout "$BASE"
	$GITENV merge --ff-only "$UPSTREAM/$BASE" || { echo "non-fast-forward merge needed; resolve manually"; exit 1; }
	echo "==> rebasing $BRANCH onto $BASE"
	$GITENV checkout "$BRANCH"
	$GITENV rebase "$BASE" || { echo "rebase conflict; resolve manually then git rebase --continue"; exit 1; }
else
	echo "==> dry run only (pass --apply to merge/rebase)"
fi

echo "==> runtime compatibility checks"
fail=0

check() {
	if eval "$2" >/dev/null 2>&1; then
		echo "  OK   $1"
	else
		echo "  WARN $1"
		fail=$((fail + 1))
	fi
}

CFG=honk/files/config.dae
LC=honk/files/lifecycle.sh

check "config.dae has dns upstream default" \
	"grep -Eq '^[[:space:]]*default:.*->[[:space:]]*direct' '$CFG'"
check "config.dae has dns upstream remote" \
	"grep -Eq '^[[:space:]]*remote:.*->[[:space:]]*proxy' '$CFG'"
check "config.dae has bootstrap_resolver" \
	"grep -Eq '^[[:space:]]*bootstrap_resolver:' '$CFG'"
check "config.dae has top-level routing block" \
	"grep -Eq '^routing[[:space:]]*\{' '$CFG'"
check "lifecycle.sh exports config_owner" \
	"grep -Eq '^config_owner\(\)' '$LC'"
check "honk init script exists" \
	"test -f honk/files/honk.init"

if [ "$fail" -gt 0 ]; then
	echo "==> $fail compatibility check(s) failed"
	echo "    Review filter.sh dns_apply()/render_config() before shipping."
	exit 2
fi

echo "==> all compatibility checks passed"
