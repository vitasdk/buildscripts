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

## Self-contained headers

`self-contained-headers.sh` compiles a translation unit per public header that
includes nothing else. A header using a type it never declares compiles for
whoever includes something helpful first, and breaks for whoever does not; the
include order of a consumer is not part of any contract.

This is the check that pthread-embedded's `<semaphore.h>` would have failed for
years: it declared `sem_open()` with `mode_t` and `sem_timedwait()` with
`struct timespec` while including nothing, and survived only because newlib's
`<stdio.h>` used to include `<sys/types.h>`.
