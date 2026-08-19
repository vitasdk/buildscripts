# softfp ABI shims

The 23 functions in `functions.tsv` are the ones where an AAPCS-base
(softfp) caller and the AAPCS-VFP (hard) Sce* stub disagree about where a
float/double argument or return value lives — see
`../artifacts/softfp-abi-audit/README.md` and `PLAN-softfp.md`, "Fase 1 - los
23 shims de serie", for how that inventory was built and why it stops at
these 23 (no kernel imports, no callbacks, no HFAs by value are affected).

## What gets built

`wrappers/*.S` (generated, checked in) are small naked Thumb-2 functions,
one per affected symbol, named exactly like the real function. Each one
moves its float/double arguments from their softfp slot into the register
the hard-float stub expects, calls into it, and — for a float/double return
— moves the result back before returning. `generate.py` derives the move
sequence from the AAPCS rules themselves (which argument gets which
register, on each side), not from a hand-picked template.

`scripts/build-softfp-shim.sh` and `scripts/patch-softfp-stub-archives.sh`
(one level up, in `buildscripts/`) assemble these wrappers and splice them
into the installed `libSceGxm_stub.a`, `libSceMotion_stub.a`,
`libScePaf_stub.a`, `libScePgf_stub.a` and `libScePvf_stub.a` (and their
`_weak` counterparts): the real object exporting e.g. `sceGxmSetViewport` is
renamed in place to `__vita_softfp_target_sceGxmSetViewport`
(`objcopy --redefine-sym`), and the wrapper is added as a new archive member
under the original name. A static archive resolves symbols through its
member index, not member order, so after the rename there is exactly one
provider of each name left — no link-order dependency, no new `-l` flag, no
GCC/LIB_SPEC patch. Packages keep linking `-lSceGxm_stub` etc. exactly as
before; see `cmake/recipes/BuildSdkComponents.cmake` (guarded by
`VITASDK_FLOAT_ABI STREQUAL "softfp"`) for where this runs in the build.

An earlier version of this plan meant to do the interception through
`LIB_SPEC` (`-lvita_softfp_shim`, unconditionally appended, "in front of the
stubs"). That does not work: GCC's `LINK_COMMAND_SPEC` expands `%o` — every
object file and every `-l` flag a caller passes explicitly — before it
expands `LIB_SPEC` (`%L`). SceGxm/SceMotion/ScePaf/ScePgf/ScePvf are never
part of the implicit baseline (unlike `SceLibKernel_stub` and friends);
every package links them explicitly, so their `-lSceGxm_stub` would always
land on the command line ahead of anything LIB_SPEC could add, and the real
stub would win the archive race every time. The archive-splice above has no
such ordering dependency.

## Regenerating

Re-run this when `../artifacts/softfp-abi-audit/scan-float-abi.py` reports a
different set of user-facing float/double crossings than `functions.tsv`
(23 rows today):

```sh
python3 generate.py ../vita-headers/include
```

`functions.tsv` (function, header path, stub module) is hand-curated, not
derived automatically — the module column especially: `scePafGraphicsUpdateCurrentWave` and `sce_paf_strtod` are both exported
from `libScePaf_stub.a` but from two different internal libraries
(`ScePafGraphics`, `ScePafStdc`), and `ScePgf` is the archive that ships the
`sceFont*` names. Re-derive it by hand (`ar t libSceXxx_stub.a`) if the
scanner's result set changes, and update it deliberately rather than
regenerating it.

The generator raises `NotImplementedError` rather than guess if it ever
meets a double or HFA parameter (none of the current 23 have one) — that
shape needs its own move-sequence case before it can be trusted.

## Known gap, not ours to close here

A caller with its own pre-existing hard→softfp wrapper (the
`vitasdk-softfp` org's vitaGL fork, built with `SOFTFP_ABI=1`) would now
double-translate if built against this series without removing that
wrapper first. Flagged for the Fase 5 migration guide, not fixed here: a new
world has no binary legacy to be compatible with, so the fix is "stop
wrapping", not a mechanism in this shim.
