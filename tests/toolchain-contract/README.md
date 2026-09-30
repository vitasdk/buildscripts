# Vita toolchain contract tests

These tests freeze the externally visible GCC 15.2.0 and binutils 2.43
behaviour used by VitaSDK before the target-specific patches are refactored.

Run after installing the SDK:

```sh
VITASDK=/path/to/vitasdk ./tests/toolchain-contract/run.sh
```

The tests intentionally describe the current ABI and driver contract. A
future change to one of these expectations must be reviewed as an ABI or
toolchain-policy change rather than being accepted as an incidental refactor.

## ELF target identification

`elf-marker.py` verifies that final links emit the non-allocated, version-1
`.note.vitasdk` target note, including ordinary GCC, `-nostdlib`, LTO,
garbage-collected, and direct `ld` links. Compilation and `ld -r` must not add
the note. It also checks that debug stripping preserves it and that the note
does not overlap any loadable segment. This test requires Python 3.

The note has owner `vitasdk` (including its null terminator), type 1, and a
four-byte descriptor with value 1. The descriptor versions the marker format,
not the SDK release. The ELF byte order applies to its integer fields.
The linker script emits the owner with `ASCIZ "vitasdk"`.

Run it separately against an installed SDK, or point `--linker-dir` at a
directory containing a newly built `ld` to test without replacing the SDK:

```sh
python3 tests/toolchain-contract/elf-marker.py "$VITASDK"
python3 tests/toolchain-contract/elf-marker.py "$VITASDK" --linker-dir /path/to/linker-bin
```

A link that replaces the default script must supply the note through its
custom script or the `vita-elf-note.ld` augmentation installed by
`vita-toolchain`. Older SDKs and deliberately unmarked custom output remain a
compatibility concern for the converter; the note identifies the target, not
authenticity.

## Self-contained headers

`self-contained-headers.sh` compiles a translation unit per public header that
includes nothing else. A header using a type it never declares compiles for
whoever includes something helpful first, and breaks for whoever does not; the
include order of a consumer is not part of any contract.

This is the check that pthread-embedded's `<semaphore.h>` would have failed for
years: it declared `sem_open()` with `mode_t` and `sem_timedwait()` with
`struct timespec` while including nothing, and survived only because newlib's
`<stdio.h>` used to include `<sys/types.h>`.
