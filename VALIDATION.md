# Validation

## 0.2.2 — the diagnostic is operator-only (2026-11-20)

Validated on Linux against SDK nightly
`0b14f8acfd97fa2c750e42795249dcc981178ca4` / mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` (`package_format` 6, `content_api`
"0.2"). Every compile step ran in a `ports/tools/build-slot.sh` lease with
`BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0` and `rm -f Cargo.lock` first; no
`--target-dir`.

| Check | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **27 passed**, 0 failed (`evidence/botanypots/sdk-test.log`) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** (`sdk-clippy.log`) |
| format | `cargo fmt --check` | `FMT_EXIT:0` (`sdk-fmt.log`) |
| package | `rm -f Cargo.lock && cargo horizon-mod build` | **62,403 B**, sha256 `f76388af…23f9` (`sdk-build.log`) |
| same package twice | the build again, `cmp` | identical (`sdk-build-second.log`, `sdk-reproducible.txt`) |
| registry check | `cargo horizon-mod check botanypots.hmod` | `botanypots 0.2.2 (native-mod, format native-1/0b14f8a…/e59da90…, for 26.3)`, 62,403 B, exit 0 (`sdk-check.log`) |
| fits | `cargo horizon-mod fits botanypots.hmod --build 0b14f8a` | `0b14f8a  made for`, exit 0 (`sdk-fits.log`) |
| package gate | `python3 ports/tools/verify-sdk-package.py botanypots` | **1/1** — 48 entries, no packed lock |
| **e2e (launcher)** | `ports/tools/launcher-game.sh run botanypots` | **`PASS` + `EXIT:0`** (`evidence/botanypots-e2e/e2e-launcher.log`) |
| **e2e (control)** | `GAME=$CONTROL_GAME` (the unmodded Nightly), same script | **`FAIL: cannot give botanypots:terracotta_botany_pot` + `EXIT:1`** (`e2e-control.log`) |
| **e2e (selftest)** | `SELFTEST=1 …` | **`FAIL: SELFTEST: the hopper pot's storage holds 1 wheat (the check is alive)` + `EXIT:1`** (`e2e-selftest.log`) |
| **e2e (slice-1 selftest)** | `SELFTEST=basic …` | **`FAIL: SELFTEST: the no-soil pot harvested nothing (the check is alive)` + `EXIT:1`** (`e2e-selftest-basic.log`) |
| log gate | `python3 ports/tools/check-e2e-logs.py botanypots-e2e --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` |

The in-game leg adds phase 8b: the launched player (an operator) reads the pot, a
non-pot position answers `not a botany pot` (naming no block), `deop` makes the same
chat command answer `Unknown or incomplete command`, and `op` restores the readout.
Every earlier phase is unchanged and still passes. The package was rebuilt after the
legs to correct `README.md`'s test count; the delivered `.hmod` differs from the copy
the launcher compiled in `README.md` only (not compiled) plus the generated `uses.json`.

## 0.2.1 — the hopper pot and the first in-game run (2026-11-20)

Validated on Linux (cargo 1.97.0, edition 2024) against SDK nightly
`0b14f8acfd97fa2c750e42795249dcc981178ca4` / mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` (`package_format` 6, `content_api`
"0.2"). Every compile step ran in a `ports/tools/build-slot.sh` lease with
`BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0` and `rm -f Cargo.lock` first; no
`--target-dir`.

| Check | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **24 passed**, 0 failed (`evidence/botanypots/sdk-test.log`) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** (`sdk-clippy.log`) |
| format | `cargo fmt --check` | `FMT_EXIT:0` (`sdk-fmt.log`) |
| package | `rm -f Cargo.lock && cargo horizon-mod build` | **61,107 B**, sha256 `2cea1f30…1279` (`sdk-build.log`) |
| same package twice | the build again, `cmp` | identical (`sdk-build-second.log`, `sdk-reproducible.txt`) |
| registry check | `cargo horizon-mod check botanypots.hmod` | `botanypots 0.2.1 (native-mod, format native-1/0b14f8a…/e59da90…, for 26.3)`, 61,107 B, exit 0 (`sdk-check.log`) |
| fits | `cargo horizon-mod fits botanypots.hmod --build 0b14f8a` | `0b14f8a  made for`, exit 0 (`sdk-fits.log`) |
| content carry | `python3 tools/carry_content.py --check` | **37 files, 0 pending** (the 131 dead recipe files dropped, see `notes.md`) |
| package gate | `python3 ports/tools/verify-sdk-package.py botanypots` | **1/1** — runtime byte-identical in tree and package, no packed lock, 48 entries |
| **e2e (launcher)** | `ports/tools/launcher-game.sh run botanypots` | **`PASS` + `EXIT:0`** (`evidence/botanypots-e2e/e2e-launcher.log`) |
| **e2e (control)** | `GAME=$CONTROL_GAME` (the unmodded Nightly), same script | **`FAIL: cannot give botanypots:terracotta_botany_pot` + `EXIT:1`** (`e2e-control.log`) |
| **e2e (selftest)** | `SELFTEST=1 …` | **`FAIL: SELFTEST: the hopper pot's storage holds 1 wheat (the check is alive)` + `EXIT:1`** (`e2e-selftest.log`) |
| **e2e (slice-1 selftest)** | `SELFTEST=basic …` | **`FAIL: SELFTEST: the no-soil pot harvested nothing (the check is alive)` + `EXIT:1`** (`e2e-selftest-basic.log`) |
| log gate | `python3 ports/tools/check-e2e-logs.py botanypots-e2e --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` |

The in-game leg runs the unmodded Nightly first in the same log (both pot ids
unknown, no pot item, no `/botanypots` command), then the full scenario on the
launcher build: both carried recipes crafted and their ingredients consumed, both
blocks placed and read back, tag membership with a stone control, the hopper
menu's 15 slots, the self-harvest into the twelve storage slots with no click, the
basic pot's 40 ready ticks yielding nothing, the export into a chest read back
through `/data get`, the full-storage overflow popped at the pot, and an unknown
`botanypots:` id refused.

## 0.2.0 — the SDK package (2026-11-18)

Validated on Linux (cargo 1.97.0, edition 2024) against SDK nightly
`0b14f8acfd97fa2c750e42795249dcc981178ca4` / mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` (`package_format` 6, `content_api`
"0.2"). Every compile step ran in a `ports/tools/build-slot.sh` lease with
`BUILD_LOCAL=1` and `CARGO_INCREMENTAL=0`; no `--target-dir`.

| Check | Command | Result |
|---|---|---|
| runtime only | `cargo test --offline` with `pub mod runtime;` | **8 passed**, 0 failed (`evidence/botanypots/sdk-test-runtime-only.log`) |
| glue red | the same, glue written as `todo!()` | 8 passed, **5 failed** (`sdk-test-red.log`) |
| tests | `cargo test --offline` | **14 passed**, 0 failed (`sdk-test.log`) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** (`sdk-clippy.log`) |
| format | `cargo fmt --check` (**not** `--all`) | `FMT_EXIT:0` (`sdk-fmt.log`) |
| package | `rm -f Cargo.lock && cargo horizon-mod build` | `Built ./target/horizon-mod/botanypots.hmod` (`sdk-build.log`) |
| registry check | `cargo horizon-mod check botanypots.hmod` | `botanypots 0.2.0 (native-mod, format native-1/0b14f8a…/e59da90…, for 26.3)`, **91,693 B**, sha256 `18218caf…e515`, exit 0 (`sdk-check.log`) |
| fits | `cargo horizon-mod fits botanypots.hmod --build nightly` | `0b14f8a  made for`, exit 0 (`sdk-fits.log`) |
| same package twice | the build again | 91,693 B, `18218caf…e515` both times, `cmp` identical (`sdk-reproducible.txt`) |
| `runtime.rs` untouched | `unzip -p botanypots.hmod src/runtime.rs \| sha256sum` | `579d8588…4076` = the port's = the retired file (`sdk-runtime-sha256.txt`) |
| content carry | `carry_content.py --check`; size + sha256 diff vs the retired content package | 159 carry files, 0 pending; **160 of 161 carried files unchanged**, `data/botanypots/license/notice.txt` refreshed (`sdk-content-carry.log`) |
| package entries | `unzip -Z1 botanypots.hmod` | **170 entries**: 7 `assets/`, 154 `data/`, 3 `src/`, `horizon-mod.toml`, `Cargo.toml`, `LICENSE`, `LICENSE-NOTICE.md`, `README.md`, `uses.json`; **no `Cargo.lock`** (`sdk-entries.log`) |
| e2e | — | **not run**: no launcher build exists here. `tools/e2e.sh` now takes `GAME=` (and optional `CONTROL_GAME=`) and keeps `SELFTEST=1` |

## 0.1.0 — the retired `.hnmod` (2026-11-09, pin `1d63e0a5`, historical)

Validated against the campaign pin `1d63e0a5…` / mixins `5a64af93…` with the
real `.hnmod` in this directory. The full table, the evidence files and the e2e
transcript are in [`notes.md`](notes.md).

| Check | Result |
|---|---|
| `cargo fmt --all --check` | pass |
| `cargo clippy --all-targets --locked --offline -- -D warnings` | pass, 0 warnings |
| `cargo test --locked --offline` | 8 passed, 0 failed |
| `python3 tools/carry_content.py --check` | 160 files, 0 pending |
| `python3 tools/horizon.py stage` | 2 modules, 9 injections |
| `python3 tools/horizon.py check` | `cargo_exit: 0`, 0 warnings |
| `python3 tools/horizon.py test` | 8 passed, 0 failed, 1240 filtered |
| `python3 tools/horizon.py build` | `cargo_exit: 0` |
| `cargo-horizon-mod build` / `check` | 47,731 B content `.hmod`, check passes |
| `python3 tools/package.py` | 12,866 B → 56,794 B `.hnmod` |
| `tools/e2e.sh` | `PASS` + `EXIT:0`; `SELFTEST=1` exits 1 |
| `python3 ports/tools/check-e2e-logs.py botanypots --strict` | `logs=4 ok=4 missing-exit=0 bad-exit=0` |
