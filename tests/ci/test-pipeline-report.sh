#!/usr/bin/env bash
# When a compression pipeline breaks, say which end broke.
#
# Under pipefail the failing status surfaces, but the message belongs to
# whichever element noticed first, and that is never the one that died: when
# xz goes, bsdtar reports "Write error: Broken pipe" against whatever file it
# was reading, and a compressor the kernel killed for memory leaves no
# message at all. Every log of this failure so far has named bsdtar and a
# file that was fine.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
script="$repository_root/scripts/create-core-package.sh"

failures=0

# The function as the script defines it, not a copy of it here.
report()
{
	bash -c '
		set -uo pipefail
		'"$(sed -n '/^report_pipeline()/,/^}/p' "$script")"'
		report_pipeline "$@"
	' report "$@" 2>&1
}

check()
{
	local description=$1 expected=$2
	shift 2
	local actual status=0
	actual=$(report "$@") || status=$?
	case $expected in
	ok)
		if ((status != 0)) || [[ -n $actual ]]; then
			printf 'FAIL: %s\n  status %s, said: %s\n' \
				"$description" "$status" "$actual" >&2
			failures=$((failures + 1))
		fi
		;;
	*)
		if ((status == 0)); then
			printf 'FAIL: %s was reported as success\n' "$description" >&2
			failures=$((failures + 1))
		elif [[ $actual != *"$expected"* ]]; then
			printf 'FAIL: %s\n  expected to contain: %s\n  said: %s\n' \
				"$description" "$expected" "$actual" >&2
			failures=$((failures + 1))
		fi
		;;
	esac
}

check "a pipeline where nothing failed says nothing" ok \
	packaging a b c xz -- 0 0 0 0

# The case this exists for. 137 is SIGKILL, which is what the kernel's
# out-of-memory killer leaves behind, and it leaves nothing else.
check "a compressor killed for memory is named, with its signal" \
	"xz killed by signal 9" \
	packaging list_package_files sort bsdtar xz -- 141 0 141 137

# And the message that used to be the only one must not be the headline: the
# upstream SIGPIPE is a consequence, so it may be reported, but the killed
# element has to be there too.
actual=$(report packaging list_package_files sort bsdtar xz -- 141 0 141 137 || true)
if ! grep -q 'bsdtar killed by signal 13' <<<"$actual"; then
	printf 'FAIL: the elements that took the SIGPIPE are not reported\n' >&2
	failures=$((failures + 1))
fi

check "an ordinary non-zero exit is reported as an exit" \
	"gzip exited 1" \
	"writing .MTREE" list_package_files sort bsdtar gzip -- 0 0 0 1

check "an element beyond the names given is still reported" \
	"element 5 exited 2" \
	packaging a b c d -- 0 0 0 0 2

# The status pipefail would have surfaced is still the status: a caller that
# was reading 137 out of this keeps reading 137.
status=0
report packaging list_package_files sort bsdtar xz -- 141 0 1 137 >/dev/null 2>&1 ||
	status=$?
if ((status != 137)); then
	printf 'FAIL: the last failing status is not preserved\n  expected 137, got %s\n' \
		"$status" >&2
	failures=$((failures + 1))
fi

if ((failures)); then
	printf '%d pipeline report check(s) failed\n' "$failures" >&2
	exit 1
fi
printf 'pipeline failure reporting: all checks passed\n'
