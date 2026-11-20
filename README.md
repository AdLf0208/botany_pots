# Botany Pots → Horizon

A Horizon port of **Botany Pots 21.1.44** (`Darkhax-Minecraft/BotanyPots`,
LGPL-2.1-only): the **botany pot** and the **hopper botany pot**, as one flat SDK
package (mod API 0.2).

- `botanypots:terracotta_botany_pot` — soil slot, seed slot, a growth tick that
  runs while the crop's soil tag accepts the pot's soil, bone meal, and a harvest
  by right-click that rolls the mature crop's own loot table; two-slot menu and a
  growth readout.
- `botanypots:terracotta_hopper_botany_pot` — fifteen slots (soil, seed, an inert
  tool slot, twelve storage), a 15-slot menu, and the hopper behaviour: a crop
  that harvests **itself** the tick it ripens into the twelve storage slots, and
  those slots pushed into the container below.
- Content: both pots' models/textures/blockstates, block declarations, menus, loot
  tables, recipes, tags, lang and item models — `assets/` and `data/` in this
  package, carried from the exact ATM10 jar
  (`../_shared/carry-work/botanypots/SOURCE.md`).
- Code: `src/runtime.rs` is the pure engine (the compiled four-crop table, the
  growth rule, bone meal, yield rolls, the hopper insert rule; 15 unit tests);
  `src/lib.rs` is the one `impl mod_api::Hooks` (the operator-only
  `/botanypots info` registration and its source re-check; 1 test); `src/pot.rs`
  is the glue (block entity Part, click Part, both containers and menus, the tick
  with the auto-harvest and export, the harvest and the readout; 11 more tests).
- Scope, deviations, the coverage table, the defects fixed and the verification
  evidence: [`notes.md`](notes.md) and [`VALIDATION.md`](VALIDATION.md).

Local-only until publishing is approved; the licence allows redistribution
under LGPL-2.1 with this complete source. `LICENSE` and `LICENSE-NOTICE.md`
travel inside the package, and the same two texts ride in `data/`.

## Build, check and play

The pinned SDK (`0b14f8a`) is fetched into `.horizon/sdk/` by any
`cargo horizon-mod` command; it is never packed.

```sh
ports/tools/build-slot.sh run --job bp --port ports/botanypots --step test -- \
    bash -c 'cd ports/botanypots && CARGO_INCREMENTAL=0 cargo test --offline'
rm -f Cargo.lock && cargo horizon-mod build          # -> target/horizon-mod/botanypots.hmod
cargo horizon-mod check botanypots.hmod              # the package check
cargo horizon-mod fits botanypots.hmod --build 0b14f8a
```

The in-game leg builds a game carrying this package with the launcher and runs
`tools/e2e.sh` in a build slot:

```sh
ports/tools/launcher-game.sh run botanypots          # PASS + EXIT:0, control leg first
SELFTEST=1 ports/tools/launcher-game.sh run botanypots   # must FAIL + EXIT:1
```

`tools/craft_check.py` is the recipe half of the leg: it crafts both carried
recipes in a real crafting table and asserts the output and that the ingredients
were consumed.
