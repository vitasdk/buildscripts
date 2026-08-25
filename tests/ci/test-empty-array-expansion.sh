#!/usr/bin/env bash
# Arrays that reach a published host must expand the way bash 3.2 tolerates.
#
# macOS runners are the reason. Their /bin/bash is 3.2, where expanding an
# empty array under `set -u` is an unbound-variable error rather than
# nothing, and the failure comes after a complete build: the SDK is
# finalized and validated, then the script dies and stages nothing. It has
# happened twice -- once fixed in "Expand possibly-empty arrays the way
# macOS's bash 3.2 tolerates", then reintroduced with the Rosetta launcher,
# which is empty for every host that runs its own binaries.
#
# The rule is mechanical on purpose. Deciding case by case which array can
# be empty is exactly the judgement that failed: `${name[@]+"${name[@]}"}`
# means the same thing as `"${name[@]}"` whenever the array has elements,
# so requiring it everywhere costs nothing and needs no judgement.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)

offenders=$(python3 - "$repository_root" <<'PYEOF'
import glob, os, re, sys

root = sys.argv[1]
# Value expansions only: ${#name[@]} and ${!name[@]} are fine in 3.2.
plain = re.compile(r'"\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}"')
tolerant = re.compile(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\+"\$\{\1\[@\]\}"\}')

for path in sorted(glob.glob(os.path.join(root, "scripts", "**", "*.sh"), recursive=True)):
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if plain.search(tolerant.sub("", line)):
                print(f"{os.path.relpath(path, root)}:{number}:{line.rstrip()}")
PYEOF
)

if [[ -n $offenders ]]; then
	printf 'these expansions die on macOS bash 3.2 when the array is empty;\n' >&2
	printf 'write ${name[@]+"${name[@]}"} instead:\n\n%s\n' "$offenders" >&2
	exit 1
fi

printf 'empty-array expansion: all checks passed\n'
