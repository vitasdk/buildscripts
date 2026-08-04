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
