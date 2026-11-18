# Validation

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
