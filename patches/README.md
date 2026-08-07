# Patch policy

Patches must be based on the exact source archive declared in
`cmake/Components.cmake` and apply with zero fuzz. Do not hide failures with
`|| true`, `-t`, or equivalent best-effort behavior.

`cmake/ApplyPatches.cmake` accepts an ordered series whose entries have the
form `absolute-path|strip-level`. ExternalProject recipes encode multiple
entries in one command-line argument with `^` separators; the script also
accepts an ordinary CMake list when invoked directly.

Before changing a source version:

1. Verify the source archive hash.
2. Extract a pristine tree.
3. Apply the complete series with `cmake/ApplyPatches.cmake`.
4. Reject fuzz, failed hunks and interactive file selection.
5. Build and run the relevant contract tests.

Keep one logical change per patch. Version updates, mechanical patch refreshes
and behavioral changes should remain separate commits.

The GDB series includes an upstream enum-flags backport required by Clang
versions where `-Wenum-constexpr-conversion` is a non-downgradeable error.

The pacman rootless-installation patch is currently a Phase 0 prototype based
on upstream pacman 7.1.0 commit
`5683f8477a0afcc6b331766175a83445b2dcfe89`. It is intentionally not part of
the superbuild until the static dependency and native host gates are closed.
