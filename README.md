# Botany Pots → Horizon

A Horizon port of **Botany Pots 21.1.44** (`Darkhax-Minecraft/BotanyPots`,
LGPL-2.1-only), slice 1: the **botany pot block**, as one flat SDK package
(mod API 0.2).

- Block: `botanypots:terracotta_botany_pot` (soil slot, seed slot, growth tick,
  bone meal, harvest by right-click), with its two-slot menu and growth readout.
- Content: the pot's models/textures/blockstate, its block declaration, menu,
  loot table, recipe, tags and the jar's vanilla crop/soil/interaction/fertilizer
  data — `assets/` and `data/` in this package, carried from the exact ATM10 jar
  (`../_shared/carry-work/botanypots/SOURCE.md`).
- Code: `src/runtime.rs` is the pure engine (8 unit tests, byte-identical to the
  0.1.0 `.hnmod` bundle's file); `src/lib.rs` is the one `impl mod_api::Hooks`;
  `src/pot.rs` is the glue (block entity Part, click Part, container, menu,
  tick, harvest and `/botanypots info`). 6 more tests pin the declarations.
- Scope, deviations, gaps and the verification table: [`notes.md`](notes.md).
  The format migration (file map, helper→hook table, its own traps and the
  changelog that supersedes PR #793) is
  [`notes.md` § Migration to the SDK format](notes.md#migration-to-the-sdk-format-020-2026-11-18).

Local-only until publishing is approved; the licence allows redistribution
under LGPL-2.1 with this complete source. `LICENSE` and `LICENSE-NOTICE.md`
travel inside the package, and the same two texts ride in `data/`.

## Build and check

The pinned SDK (`0b14f8a`) is fetched into `.horizon/sdk/` by any
`cargo horizon-mod` command; it is never packed.

```sh
ports/tools/build-slot.sh run --job bp --port ports/botanypots --step test -- \
    bash -c 'cd ports/botanypots && CARGO_INCREMENTAL=0 cargo test --offline'
rm -f Cargo.lock && cargo horizon-mod build          # -> target/horizon-mod/botanypots.hmod
cargo horizon-mod check botanypots.hmod              # the package check
cargo horizon-mod fits botanypots.hmod --build nightly
```

An in-game run needs a game built by the launcher with this package
(`horizon-launcher native-build . --trust-native-code`); `tools/e2e.sh` takes it
as `GAME=` and keeps its fail-capable `SELFTEST=1` leg. No launcher exists in
this environment, so no 0.2.0 in-game run is claimed — see `notes.md`.
