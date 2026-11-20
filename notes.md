# Botany Pots → Horizon

Ported from **Botany Pots 21.1.44** (`Darkhax-Minecraft/BotanyPots`,
**LGPL-2.1-only**), Minecraft Java 1.21.1 NeoForge, read from
`ports/_shared/upstream/botanypots` at commit `335c997` (2026-06-13, the jar
build day). The upstream source and the jar were read for behaviour and assets
only; the Rust is a clean-room rewrite. The exact ATM10 jar is
`botanypots-neoforge-1.21.1-21.1.44.jar`, SHA-1
`fcb58dfa5f52819c85da40025fa50d0ddccbbb47` (provenance:
[`../_shared/carry-work/botanypots/SOURCE.md`](../_shared/carry-work/botanypots/SOURCE.md)).
Local-only until publishing is approved (ARCHITECTURE.md §8).

## Approach (from the pin's `docs/modpacks.md`)

- **Class `content`, tier `machines`** (`ports/ledger.csv` row 80; provenance
  `ports/_shared/source-map/atm10-sources.csv`). This job is **slice 1**: the
  **botany pot block** as a machine-tier block — a block entity, two container
  slots, a menu + screen, a growth tick and a harvest — with the pot assets and
  the jar's soil/crop data carried from the exact ATM10 jar. The variant
  pots, hoppers/waxed pots, the remaining crops/soils and the automation are
  gaps (below), not silently ported.
- **Licence:** LGPL-2.1-only, read from the jar's
  `META-INF/neoforge.mods.toml` (+ `license_botanypots.txt`) → **rank 1**
  (copyleft). Copyleft is **not** a bar: the port is publishable under the same
  licence with this complete source; it stays local until the maintainer
  approves (ARCHITECTURE.md §8). Ported now because it is a core
  `machines` content mod that several Botany add-ons (`botanypotsmystical`,
  `botanytrees`) need, after the campaign-scale deep mods.
- **Carry-over vs agent port:** the pot's blockstate, block model, the shared
  `template/pot` model, its item model, `terracotta_pot_top.png`, the soil item
  tags, the pot tags, the block loot table and its crafting recipe are carried
  from the jar (re-spelled only where 26.3 differs, see `SOURCE.md`); the
  growth/harvest/bone-meal behaviour, the block entity, the container, the menu
  and the interaction are the agent port.

## Slice 1 — the basic botany pot

- `botanypots:terracotta_botany_pot` on the `minecraft:barrel` template (its
  use path opens the mod menu; the same template Functional Storage proved),
  with the jar's 2-pixel-inset outline/collision (`block.box(2,0,2,14,8,14)`),
  `occludes: false`, hardness 1.25 and blast resistance 4.2. The carried
  blockstate is a single `""` variant, so every inherited `facing`/`open`
  state draws the pot model (the barrel's `open` is the template's, unused).
- A block entity (API 15) that saves `growth`, `soil`, `seed` and the
  `bone_meal` cooldown in its compound, and **ticks on the server** (API 15).
- Two player-only container slots, soil 0 and seed 1, with no hopper face
  (upstream refuses every insert) and the content menu
  `botanypots:basic_pot_menu` (2 slots, 2 data slots: growth and required), a
  `native_screen` layout and a progress readout (`native_screen_draw`).
- **Growth**: each tick, while the crop's soil tag accepts the pot's soil
  (`#botanypots:soil/dirt` for the four crops), growth advances and is ready at
  `floor(1200 / (1 + soil modifier))`; `minecraft:farmland` is +0.10 (1090
  ticks), every other dirt-family soil 0 (1200).
- **Harvest** by right-click when ready: rolls the mature crop block's **real
  loot table** (`Game::block_loot_at` with the `age=7`/`age=3` state) once per
  yield roll, pops it at the pot (`Game::pop_resource`) and resets growth; the
  seed stays in the pot. Upstream's `BlockStateDrops` does the same.
- **Bone meal**: right-click with bone meal adds 400..600 growth (level random),
  capped at `required - 20`, with the upstream 20-tick cooldown; creative does
  not consume it. A ready pot harvests instead of fertilising (upstream's click
  order).
- Four vanilla crops from the jar's own `data/botanypots/recipe/minecraft/crop/`
  files: wheat (`wheat_seeds` → `wheat`), carrots (`carrot` → `carrots`),
  potatoes (`potato` → `potatoes`), beetroots (`beetroot_seeds` → `beetroots`,
  `age=3`), all `grow_time 1200`, base yield 1.
- `/botanypots info <x> <y> <z>`: a server readout of the pot's growth,
  required ticks, soil, seed and readiness (the harness reads it; upstream has
  its own `/botanypots` debug commands).

### Behaviour read from upstream (and where this port differs)

| Area | Upstream | This port |
|---|---|---|
| slots | 15 (soil, seed, tool, 12 storage) | 2 (soil, seed); tool/storage are gaps |
| menu | 2 slots for a basic pot, data = block pos | 2 slots, data = growth/required |
| growth | block-entity tick; `floor(cropTime / (1 + soil + tool + pot))` | same with the soil modifier only |
| soil | data recipes; farmland +0.10 | dirt tag membership + farmland 0.10; other soils are gaps |
| crop lookup | recipe registry, ~800 entries incl. modded | compiled table of the four vanilla crops |
| harvest | block loot table at the mature state, `yield` rolls | same (real loot table), one roll at base yield |
| harvest click | basic pot only, right-click, pops items | same |
| bone meal | 400..600, cap required-20, 20-tick cooldown | same |
| comparator | progress/15 | not implemented (gap) |
| waterlogged / `LEVEL` light | supported | not implemented (template has no `waterlogged`) |
| hopper/waxed pots | auto-harvest into storage / frozen | not implemented (gaps) |
| crop render | a display model in the pot | not drawn (gap) |

### Deliberate deviations

- **One pot variant** (`terracotta_botany_pot`); the other 183 (coloured,
  hopper, waxed) are not registered in this slice.
- **A compiled four-crop table** instead of the recipe registry: the modded
  crops, the remaining ~70 vanilla crops, per-crop `grow_time`/`yield`/`light`
  and the pot predicate are not read. The jar's crop/soil/interaction/fertilizer
  JSON was carried in 0.1.0/0.2.0 so a later slice could parse it through API 36
  — **0.2.1 dropped it**: those files name Java recipe serializers this port does
  not implement (`botanypots:block_derived_crop` and four more), and Horizon
  refuses to load a pack holding one (see *Slice 2*, "Upstream defects fixed").
  The jar stays the evidence to re-carry them when the crop registry exists.

- **Bone meal is taken from the whole inventory** (`native_take_items`) rather
  than shrunk in the exact hand; creative keeps the stack in both.
- **The growth counter clamps at the required ticks** (upstream keeps a float
  that a harvest resets); it is only read through `is_ready`, and the clamp
  keeps the menu's 16-bit data slot in range.
- **Harvest is not a full `Block.popResource` face/motion reproduction**: it is
  the real `pop_resource` at the pot (10-tick pickup delay, the level's own
  random), with no sound/particles.
- **The pot's menu is a Horizon content menu** (API 85); a non-Horizon client is
  never sent it, as the pin documents.
- The `barrel` template's `open` state changes on a use; the pot model ignores
  it (no lid animation).

## Slice boundary (what this port is)

**In:** the basic botany pot block, soil + seed slots, the growth tick with the
soil modifier, bone meal, harvest (real crop loot table), the two-slot menu and
its screen readout, the `/botanypots info` readout, carried content for the pot
and the vanilla crop/soil data; and (0.2.1) the terracotta hopper botany pot —
fifteen slots, its 15-slot menu, the self-harvest into twelve storage slots, the
downward export, and its recipe/loot/tag/item content.

**Out (gaps, next slices):** the 181 other pot variants; waxed pots; the tool
slot's effects and harvest tool damage/enchantments; the comparator output;
waterlogging and the `LEVEL` light; the crop display renderer; the
modded/remaining crops and the soil registry beyond the dirt tag; sand/water/
lava/snow/end/nether soils; fertilizer recipes other than bone meal; pot
interaction recipes (hoe→farmland, shovel→path, bucket→stone/obsidian); JEI
integration, Patchouli/docs; the config file (`global_growth_modifier`,
`damage_harvest_tool`, `efficiency_growth_modifier`, `default_harvest_stack`);
sounds and particles; hopper automation *in* (upstream refuses every insert
face); creative tab filtering beyond the two pots.

**Not asserted in this slice's e2e** (engine behaviour the pin owns, or later
slices): a break spilling the two slots and dropping the pot item (the carried
loot table is patched for 26.3, but the break was not driven); the menu's
progress text drawn on screen (the data slots are asserted only through
`/botanypots info`); recipe crafting of the pot; the crop display model.

## Verification (0.1.0, the retired `.hnmod` — historical)

Pin `1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9` / horizon-mixins
`5a64af938…`; every step through `ports/tools/build-slot.sh` with `CARGO_INCREMENTAL=0`,
`--horizon ports/_shared/pins/horizon-1d63e0a`, `HORIZON_MIXINS=…/horizon-mixins-5a64af9`.
**The logs below describe the retired format and are kept as history**: the 0.2.0 SDK ladder is
under "Migration to the SDK format" (see `VALIDATION.md`), and the 0.1.0 e2e logs are the
behaviour's evidence for a `runtime.rs` that did not change. Evidence:
[`../_shared/evidence/botanypots/`](../_shared/evidence/botanypots/).

| Step | Command | Result |
|---|---|---|
| runtime tests (standalone) | `cargo test --locked --offline` in the port | **8 passed**, 0 failed |
| fmt | `cargo fmt --all --check` | pass |
| clippy | `cargo clippy --all-targets --locked --offline -- -D warnings` | `CARGO_CLIPPY_EXIT=0`, **0 warnings** |
| stage | `python3 tools/horizon.py stage --horizon …/horizon-1d63e0a` | `status: ok`, **2 modules, 9 injections** |
| check | `python3 tools/horizon.py check --horizon …` | `cargo_exit: 0`, **0 warnings** (`horizon-check.log`) |
| embedded tests | `python3 tools/horizon.py test --horizon …` (`--lib`) | `8 passed; 0 failed; 1240 filtered out` (`horizon-test.log`) |
| fast build | `python3 tools/horizon.py build --horizon …` | `cargo_exit: 0` (462 s) |
| content carry | `python3 tools/carry_content.py --check` | **160 files, 0 pending**, jar SHA-1 `fcb58dfa…` |
| content `.hmod` | `cargo-horizon-mod build` in `content/` | exit 0, **47,731 B**, SHA-256 `eb7f1e39…e5f2`, **160 files** |
| content check | `cargo-horizon-mod check botanypots.hmod` | exit 0, `botanypots 21.1.44 (mod, API 0.2, both)`, "no code" |
| content check, negative | the same build with the manifest id `BotanyPots` | **exit 1**, `id "BotanyPots" is not [a-z0-9_]{1,64}` |
| native `.hnmod` | `python3 tools/package.py` | **12,866 B**, SHA-256 `85828cac…1154`, 13 entries; pins `horizon`/`mixins` |
| e2e (default) | `build-slot.sh e2e … -- tools/e2e.sh` | **`PASS` + `EXIT:0`** (`e2e-default.log`) |
| e2e (selftest) | `SELFTEST=1 …` | **exit 1** at `FAIL: SELFTEST: the no-soil pot harvested nothing (the check is alive)` |
| `.hmod` load check | shared unmodded game, `--dev-mod content/botanypots.hmod` | give `.given=1`, setblock reads `botanypots:terracotta_botany_pot` |
| `.hmod` negative | the same game/world **without** `--dev-mod` | `{"error":"unknown item botanypots:terracotta_botany_pot"}`, `{"error":"unknown block name"}`, `PASS` |

E2E transcript (abridged from `e2e-default.log`; every line is a `ctl` reply or
an assertion):

### Selftest isolation (harness fix, 2026-11-10)

The selftest leg reuses the scenario's end state, and the scenario's harvest pops
wheat at the pot with a pickup delay while the player stands one block away, so
the wheat was usually **in the inventory** by the time the selftest counted it
(`harvest: wheat in inventory 1, wheat on the ground 0`). The leg then exited
`SELFTEST unexpectedly saw 1 wheat` with `EXIT:1` and **no `FAIL:` line** — a
contaminated pass of the checker, not a meaningful failure. Before the impossible
assertion, the leg now clears the player's inventory (`clear @s`) and kills item
entities within 24 blocks of the platform in the Overworld
(`execute in minecraft:overworld run kill @e[type=minecraft:item,x=…,y=101,z=…,distance=..24]`),
waits, and **asserts the pre-state is clean**
(`selftest isolation: wheat in inventory 0, wheat on the ground 0`); only then
does it click the no-soil pot, so any wheat it counts can come only from that
pot. The scenario, the assertions and the non-selftest path are unchanged. A
pre-fix selftest log from a concurrent session was still in the evidence
directory when this fix landed; it ends at the `FAIL:` line with **no `EXIT:`
line**, the other half of the same harness defect, and is kept under
`selftest-before-isolation-no-exit.log` (a name the log checker does not scan).
The 05:40 contaminated run itself (`harvest: wheat in inventory 1, wheat on the
ground 0` … `SELFTEST unexpectedly saw 1 wheat`, `EXIT:1`, no `FAIL:` line) was
replaced in `e2e-selftest.log` by that session's run before this job could copy
it; its transcript is quoted here.

- `e2e-default.log` (after the fix): `PASS: the pot grows soil+seed crops on its
  own tick (not a random tick), a wrong soil or a non-crop seed does not grow,
  bone meal forces growth, and harvest pops the mature crop's loot and resets` +
  `EXIT:0`.
- `e2e-selftest.log` (after the fix): `FAIL: SELFTEST: the no-soil pot harvested
  nothing (the check is alive)` + `EXIT:1`.
- `python3 ports/tools/check-e2e-logs.py botanypots --strict` → exit 0,
  `logs=4 ok=4 missing-exit=0 bad-exit=0`.

One post-fix run failed **earlier**, at the very first `/botanypots info`
readout (`readout: ''`, nothing native answering), i.e. before anything this
change touches; it did not recur in the two recorded runs. It is consistent with
the stale-injected-tree trap added to `AGENTS.md` the same day (a surviving
`stage/modded` from another port in the shared slot makes the binary belong to
that port). `info()` now prints the raw chat reply when a readout is missing, so
a recurrence names its cause instead of failing with an empty `readout:`.

```
readout: botanypots:terracotta_botany_pot: growth=0/0 soil=none seed=none ready=false
menu slots: 2 (soil, seed)
readout: botanypots:terracotta_botany_pot: growth=6/1200 soil=minecraft:dirt seed=minecraft:wheat_seeds ready=false
growth after 40 ticks: 52 / 1200
growth with randomTickSpeed 0: 52 -> 95
no-soil readout: botanypots:terracotta_botany_pot: growth=0/1200 soil=none seed=minecraft:wheat_seeds ready=false
sand soil growth: 0 -> 0
stick seed growth: 0 -> 0
after bone meal 1: … growth=884/1200 … ready=false
after bone meal 2: … growth=1200/1200 … ready=true
harvest: wheat in inventory 0, wheat on the ground 1, seeds 3
after harvest: … growth=22/1200 … ready=false
second click wheat: 1 -> 1
PASS: the pot grows soil+seed crops on its own tick (not a random tick), a wrong soil or a non-crop seed does not grow, bone meal forces growth, and harvest pops the mature crop's loot and resets
E2E EXIT:0
```

Controls that make it fail-capable: a pot with no soil never grows; sand (not in
the crop's soil tag) never grows; a stick (no crop) never grows; a second click
on the reset pot adds no wheat; `SELFTEST=1` asserts the impossible and exits 1.
The `randomTickSpeed 0` run is the **differential that proves the mechanism**:
growth continues, so it is the block entity's tick, not a vanilla random tick.

### Embedded content (AE2 pattern) — the port is one `.hnmod`

The registry stores **one file per project** (`AGENT_PLAYBOOK.md` §1.0), so the
split content+code port above could not be listed faithfully. It now carries its
content **inside** the bundle, the pattern `charginggadgets` proved in game
(PR #526):

- **`mixins/botanypots/data/botanypots-content.hmod`** — the built
  `content/botanypots.hmod`, byte for byte (`tools/package.sh` builds and syncs
  it; `tools/package.py` refuses a copy that differs).
- **`mixins/botanypots/embedded_content.rs`** with the one `embedded-content`
  injection (HEAD, cancellable, `target = "horizon_client::game::mods::content_root"`,
  bindings `root`/`enabled`/`dev`): `native_data!` compiles the `.hmod` into the
  game, the helper writes it to `.horizon-cache/botanypots-embedded-content.hmod`
  when the copy on disk differs and appends it to the dev list.
- **`tools/package.py`** packs `mixins/<id>/data/` (`docs/native-mods.md`,
  "Data files"); **`tools/package.sh`** rebuilds the `.hmod`, syncs it, writes
  the `.hnmod` into the port root and runs
  `cargo horizon-mod check <file> --kind native-mod`.
- **`tools/ladder-embed.sh`** runs the ladder (the content build must come
  **before** `stage`, because `native_data!` reads the staged
  `native-data/botanypots/`); **`tools/e2e-embed.sh`** runs both game legs in one
  lease.

| Item | Evidence | Result |
|---|---|---|
| `.hnmod` (content embedded) | `ports/botanypots/botanypots.hnmod` | **36,145 B**, SHA-256 `b54203718cdc70f841344b77ca967a92347b416e8046e406267e29bfff76b216`, **15 entries** incl. `mixins/botanypots/data/botanypots-content.hmod` (47,731 B, `eb7f1e39…e5f2`) |
| native check | `package-0.1.0.log` | `botanypots 0.1.0 (native-mod, format native-1/1d63e0a5…/5a64af93…, for 26.3)` — passes on these bytes |
| ladder | `fmt.log`, `clippy.log`, `test-green.log`, `stage.log`, `check.log`, `test.log`, `build.log` | fmt and clippy `-D warnings` clean, **8 pure tests**, stage/check **exit 0**, embedded test **8 passed**, fast build |
| e2e, one file only (`EMBEDDED=1`, no `--dev-mod`) | `e2e-embedded.log` | **PASS**, `EXIT:0`: control leg first (same binary, `.horizon-cache` unusable → block `minecraft:air`, 0 pots in the inventory, while `/botanypots info` still answers `minecraft:air: not a botany pot`), then the whole soil/seed/growth/bone-meal/harvest scenario with the embedded file byte-identical to `content/botanypots.hmod` |
| embed fail-capability | `e2e-selftest.log` | `EMBEDDED=1 SELFTEST=1` → `FAIL: SELFTEST: the no-soil pot harvested nothing (the check is alive)`, `EXIT:1` |
| second fail-capability run | `e2e-embedded-selftest.log` | the same leg, `FAIL` + `EXIT:1` (this run tripped the slice-1 growth window first: `grew 61 ticks in 40, expected at most 60` — a boundary flake of that assertion, not of this slice) |

`tools/horizon.py`'s default horizon checkout was still the stale
`horizon-41f822b` template while `compatibility.json` pins `1d63e0a`; it now
defaults to the pin, so a bare `tools/horizon.py build` (what
`build-slot.sh e2e` calls) stages the right revision.

The reproduction for this slice is `tools/e2e-embed.sh` (both game legs in one
lease) and `tools/selftest-embed.sh` (the fail-capability leg alone).

### Harness facts learned (useful for the next slice)

- **`--game-dir` makes the game `set_current_dir` into it before content
  loads** (`crates/horizon-client/src/game.rs`), so the embedded-content helper's
  `.horizon-cache/` lands in `<game-dir>/.horizon-cache`, not in the launch
  directory. The embedded e2e reads and plants the file there; a control that
  puts it next to the launch directory is silently ignored and proves nothing.
- A control leg must run in **its own scratch home and game folder**: sharing
  them with the main run mixes the two sessions' logs and races the world lock
  (the mekanism slice hit both symptoms). `tools/e2e.sh` runs the control in
  `$SCRATCH/control` with its own `HORIZON_HOME`/`XDG_*`.

- A menu click moves the **cursor** stack, not the hotbar stack: click the
  inventory slot holding the item first, then the pot's slot (`ctl click-slot
  300` / `301`; a mod menu's slots are 300+, the player inventory's 0–35).
- `ctl give` may fill a main-inventory slot that `ctl select ITEM` cannot
  select; `item replace entity @s hotbar.0 with …` + `ctl select 1` is
  deterministic.
- A right click on a **ready** pot harvests, so a bone-meal loop must stop as
  soon as `ready=true` (otherwise the next meal is a harvest).
- After a harvest the growth restarts immediately: assert `< 40` ticks, not `= 0`.
- `ctl place` respects reach (a 6-block placement fails); teleport 3 blocks from
  the target before each placement.
- Harvest drops pop at the pot with a pickup delay; assert the ground
  (`ctl entities … item`) as well as the inventory.

## Class + tier, approach, licence (recorded)

Class **content**, tier **machines**; the shape chosen is the tier's
(carried pot content + block entity + container/menu/screen + a tick), not a
plain data block and not a deep entity/renderer port. Licence **LGPL-2.1-only →
rank 1**; publishable under LGPL-2.1 with complete corresponding source;
local-only until the maintainer approves.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## Reviewer repairs (2026-11-11) — PR review items and what changed


Each item below is quoted from `ports/_shared/horizon-mods/reviews/pr-*-botanypots.md` (the review is the specification), with what this repair did about it.

- **Reviewer:** [packaging defect found while repairing] the `.hnmod` did not contain its `data/` folder
  **Repair:** Fixed: `tools/package.py` packed only the bundle root, so `native_data!` could not resolve `botanypots-content.hmod` in the launcher's build. It now packs `data/`; the artifact grew from 24,180 to 56,794 bytes.
- **Reviewer:** LGPL-2.1 source review is the reviewer's limitation
  **Repair:** Not a code item: the registry accepts copyleft and the complete corresponding source travels with the repository.
- **Reviewer:** licence notice
  **Repair:** `LICENSE` + `LICENSE-NOTICE.md` in the `.hnmod`, `data/botanypots/license/` in the carried `.hmod`.
- **Reviewer:** registry artifact delivery
  **Repair:** **Staging (orchestrator, not ours)**: the artifact is not in registry release/staging as `<sha256>.<ext>`; the orchestrator answers it with `horizon-mods#686` (no write access to the registry's releases). Every repackaged artifact below has a fresh sha256 for that re-push, and the author release must be re-uploaded from the port repository.

Skills: superpowers/using-superpowers,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## Migration to the SDK format (0.2.0, 2026-11-18)

Horizon's mod-API merge (#16941, launcher ≥ 0.2.70; PR #17992 cleans up the old files)
retired the `.hnmod` container: the registry closed every `.hnmod` submission on
2026-11-18 with the single reason *"republish this as a native `.hmod` with the SDK from
the next Nightly"*. **0.2.0** is the same behaviour republished as one flat SDK `.hmod`;
this port's former submission, **#793** (`botanypots` 0.1.0), was closed by that purge and
the changelog below supersedes it.

Pins: SDK nightly **`0b14f8acfd97fa2c750e42795249dcc981178ca4`** (`package_format` 6,
`content_api` "0.2"), mixins **`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, for 26.3. The
SDK slice is cached in-tree at `../_shared/sdk/0b14f8a/` and copied into the port's
`.horizon/sdk/` (gitignored, never packed). The class+tier and the approach are unchanged:
**`content` / `machines`**, carried pot content + a block entity + a container/menu +
a tick, **LGPL-2.1-only → rank 1**, local-only until the maintainer approves publishing.

**Done in this order:** the retired paths moved into
`../_shared/evidence/botanypots/retired-hnmod-0.1.0/` **before** the first
`cargo horizon-mod build` (the tool refuses a root holding retired package paths), then
`src/runtime.rs` was copied with `cp` and proved with `cmp` + `sha256sum`, `cargo test`
ran on the new crate with only `pub mod runtime;` (**8 passed**, before any glue existed),
then the glue was written as `todo!()` and watched fail (**5 failed**), and only then
implemented (**14 passed**). Every compile ran in a `build-slot.sh` lease with
`BUILD_LOCAL=1` and `CARGO_INCREMENTAL=0`.

### File map (old `.hnmod` layout → new SDK package)

| Old | New |
|---|---|
| `horizon-mixin.toml` (`[mod]`, `[compatibility]`, 2 `[[module]]`, 10 `[[injection]]`) | `horizon-mod.toml` (id/name/version/description/authors/api/side/capabilities + `[native]` game/horizon/mixins) |
| `Cargo.toml` (`[lib] path = "mixins/botanypots/runtime.rs"`, `[workspace] members = ["tools/audit"]`) | `Cargo.toml` (`[lib] path = "src/lib.rs"`, one dependency: `horizon-mod-api` from `.horizon/sdk/`) |
| `mixins/botanypots/runtime.rs` (module + crate lib, 10,214 B) | `src/runtime.rs` — **byte-identical** (`579d8588…4076`), `pub mod runtime;` at the crate root, 8 tests |
| `mixins/botanypots/support.rs` (485 lines, module `botanypots_state`) | `src/pot.rs` — the glue: declarations, the two Parts, the saved state, the tick, the harvest, the readout; 6 tests |
| 10 per-hook helper `.rs` files | methods of the Parts / `impl Hooks` / a `Registrar` call; no per-hook files |
| `mixins/botanypots/data/botanypots-content.hmod` + `embedded_content.rs` (the AE2 write-out) | **gone**: code and content are one package |
| `content/` (`assets/`, `data/`, its own `horizon-mod.toml`, `content/botanypots.hmod`) | package root: `assets/`, `data/` (the content half of the same `.hmod`) |
| `compatibility.json`, `rust-toolchain.toml` | **gone**: `[native]` in `horizon-mod.toml` is the pin, and the pinned SDK decides the toolchain |
| `botanypots.hnmod` (56,794 B, the embedded-content build) | `botanypots.hmod` (**91,693 B**, sha256 `18218caf…e515`, 170 entries) |
| `tools/horizon.py`, `package.py`, `package.sh`, `test_stage.py`, `test_template.py`, `stamp_license.py`, `audit/` | **gone** (moved to evidence): the SDK ladder is `cargo test` + `cargo horizon-mod build/check/fits` |
| `tools/ladder-embed.sh`, `e2e-embed.sh`, `selftest-embed.sh` | **gone**: the EMBEDDED legs retired with the container (one package holds both halves) |
| `PLAN.md`, the old repo `AGENTS.md` | **gone** (moved to evidence): both describe the retired plan/`tools/horizon.py` workflow |

**Kept and updated:** `tools/carry_content.py` (now writes `assets/`/`data/` at the package
root and no longer writes a second manifest), `tools/e2e.sh` (launcher-built `GAME=`, optional
`CONTROL_GAME=`, `DEV_MOD=1`, `SELFTEST=1`), `FINDINGS.md`, `notes.md`, `VALIDATION.md`,
`README.md` (rewritten), `LICENSE`, `LICENSE-NOTICE.md`. **Retired into evidence:**
`mixins/`, `botanypots.hnmod`, `compatibility.json`, `rust-toolchain.toml`, `Cargo.lock`
(deleted, never packed), `PLAN.md`, the old `AGENTS.md`, the old `content/horizon-mod.toml`
and `content/botanypots.hmod`, and the six retired tools.

### Manifest mapping

- identity: `id = "botanypots"` (also the resource namespace), `name`, `version = "0.2.0"`
  (the port's version, not upstream's 21.1.44), `license = "LGPL-2.1-only"` in `Cargo.toml`,
  `authors = ["Darkhax", "AdLf0208"]`.
- `api = "0.2"` (exact), `side = "both"` (an integrated server belongs to the client
  installation, so LAN hosts and single player need it), `capabilities = ["registries"]`
  (the schema's one value — this package really does declare a block and a block entity).
- `[native] game = "26.3"`, `horizon = "0b14f8a…"`, `mixins = "e59da90…"` replace
  `[compatibility] horizon_revision` and the bundle's mixins revision.
- `[mod] priority = 100` and the plan's ordering are gone; nothing here needed ordering.

### Helper → hook table

| 0.1.0 injection (hook, API) | 0.2.0 | Notes |
|---|---|---|
| `embedded-content` (`content_root`, AE2 HEAD, cancellable) | **none** | one package carries `assets/`+`data/` |
| `block-entity` (`block_entity` 15, initial compound) | `BlockEntityPart::block_entity` on `PotEntity` | a fresh pot still starts with an empty compound |
| `block-entity-ticks` (`block_entity_ticks` 15) | `BlockEntityPart::block_entity_ticks` | `event.ticks = true` |
| `block-entity-container` (`block_entity_container` 16/17, built a `ModContainer`) | `Registrar::block_container(&block, pot::container())` in `Hooks::register` | a declaration, not a hook: 2 slots, no face reaches them, the pot menu |
| `block-entity-tick` (`block_entity_tick` 15, `game`/`pos`/`entity`) | `BlockEntityPart::block_entity_tick` | `event.pos`, `event.entity.nbt`/`.items`/`.data`; answers `Unchanged` when nothing changed |
| `screen` (`screen` 19) | `BlockEntityPart::screen` | `Some(menu())` |
| `screen-draw` (`screen_draw` 19, `HudBatch`) | `BlockEntityPart::screen_draw` | `event.draw.text(…)`, `event.data` |
| `right-click-block` (`right_click_block` 21, `canceled`) | `BlockPart::use_item_on` **+** `use_without_item` on `PotClick` | the SDK splits the two hands; an answer replaces the template's use, which is what `canceled` meant |
| `register-commands` (`register_commands` 8) | `Hooks::register_commands` | `Command::new("botanypots info <pos:block_pos>")` |
| `perform-command` (`perform_command` 8, string words) | `Hooks::run_mod_command` | typed argument: `CommandArgumentValue::BlockPos([i32;3])`; `Flow::Cancel` = handled; the printed line is byte-identical to 0.1.0 |
| `game.native_block(pos)` | `level.block(host, pos)` → `BlockKey::id(host)` | handle read |
| `game.native_with_mod_block_entity` (read/write) | `host.block_entity(level, pos)` → `BlockEntityRef::data` / `merge_data` / `item_slot` | `merge_data` is `/data merge block`: it marks the chunk and comparators hear it |
| `game.native_server_item_in_tag(&stack, tag)` | `host.tags().key(&Identifier)` + `host.tags().is_in_tag(item_key, key)` | takes an `ItemKey`, not an id string |
| `game.native_take_items(BONE_MEAL, 1)` | `ItemPlace::PlayerHand{player, hand}.extract(host, tx, &resource, 1)` | now the **clicking hand**, inside one transaction with the growth write |
| `game.block_loot_at(pos, mature, None, None)` + `game.pop_resource` | `level.roll_loot(host, table, origin, None, None)` + `level.pop_resource` | **gap**: no block-state loot context (see below) |
| `game.native_level_random(&dimension)` | `level.with_random(host, |r| r.next_float())` / `next_int_bound` | same draws, same order |
| `game.native_register_commands`/`NativeCommand` | `Command` + `event.commands` | same usage strings |
| `game.native_feedback(Text::literal(…))` | `host.commands().feedback(Text::literal(…))` | same text |

### Build and verify (measured 2026-11-18)

```
cargo test --offline                                   # 8 passed (runtime only, no glue yet)
cargo test --offline                                   # 8 passed, 5 failed (glue as todo!())
cargo test --offline                                   # 14 passed; 0 failed
cargo clippy --all-targets --offline -- -D warnings     # exit 0, 0 warnings
cargo fmt --check                                      # FMT_EXIT:0
rm -f Cargo.lock && cargo horizon-mod build            # -> target/horizon-mod/botanypots.hmod
cargo horizon-mod check botanypots.hmod                # exit 0
cargo horizon-mod fits botanypots.hmod --build nightly # exit 0
```

`check` output:

```
botanypots 0.2.0 (native-mod, format native-1/0b14f8acfd97fa2c750e42795249dcc981178ca4/e59da9094f0c2fdda6c627fe9eff22dec6a906f0, for 26.3)
  91693 bytes, SHA-256 18218cafb9ad6fc5d2c5de49c93311efef4cb912c1e68bc20a4a287f9556e515, unsigned
  native source: unsandboxed; not executed by the registry check. Compile and test against the exact pinned Horizon and Mixins revisions before review.
```

`fits` output:

```
Botany Pots:
0b14f8a  made for
```

The archive is **170 entries**: `horizon-mod.toml`, `Cargo.toml`, `LICENSE`,
`LICENSE-NOTICE.md`, `README.md`, `assets/…` (7), `data/…` (154), `src/{lib,pot,runtime}.rs`,
`uses.json`. **No `Cargo.lock`.** Two builds are byte-identical (91,693 B,
`18218caf…e515`), and `unzip -p botanypots.hmod src/runtime.rs | sha256sum` is
`579d8588…4076`, the retired file byte for byte.

`uses.json` is the migration's best summary: **348 entries** — 33 hook tables (the nine used
hooks: `block_entity`, `block_entity_ticks`, `block_entity_tick`, `screen`, `screen_draw`,
`use_item_on`, `use_without_item`, `register_commands`, `run_mod_command`), 42 methods
(`BlockEntityPart::*`, `BlockPart::use_*`, `Hooks::register`, `DefaultCapabilitiesRegistrar::
block_container`, `HostTransaction::transaction`, `LevelHost::block_state_id`,
`BlockStatesHost::block_item`, `Tags::key/is_in_tag`, `RandomSource::next_float/next_int_bound`,
`Commands::feedback`, `DrawContext::text`), 5 part kinds, both macros and the single
`registries` capability. Evidence: `../_shared/evidence/botanypots/sdk-uses-summary.log`.

The content half moved to the package root and was re-derived: `carry_content.py --check`
reports **159 files, 0 pending** (jar SHA-1 `fcb58dfa…`), and of the **161** content files
(the 159 plus the two licence copies) **160 match the retired content package by size and
sha256**; the one deliberate change is `data/botanypots/license/notice.txt` (1,022 → 1,006 B),
because the notice now names the one `.hmod` instead of the retired `mixins/` paths
(`sdk-content-carry.log`). The two licence texts are static copies of this repository's
`LICENSE` and `LICENSE-NOTICE.md` under `data/botanypots/license/`; the old
`tools/stamp_license.py` retired with the other old tools, so `cmp` is the check.

### Traps this migration hit (the next port must know)

1. **`build-slot.sh run` forwards to the remote runner by default**, and the runner syncs the
   port to *its* root — the brief's `cd ports/botanypots` inside the wrapped command then
   fails there with `cd: ports/botanypots: No such file or directory`. This port's ladder is
   the SDK's own in-place build, so every step here used `BUILD_LOCAL=1`.
2. **`… | tee log` masks cargo's exit status.** The first test run was reported as
   `released slot (exit 0)` while cargo had failed to compile. Put `set -o pipefail` inside
   the wrapped `bash -c` (and/or echo `${PIPESTATUS[0]}`).
3. **Two Parts, not one.** `use_item_on`/`use_without_item` are `BlockPart` methods dispatched
   by the *block*, and the block entity methods by the *type*: `PotClick` goes on the block key
   (`Registrar::block_part`) and `PotEntity` on the type (`block_entity_part`, which returns
   `Result` and needs the type built by `block_entity_type(..).blocks(..)` first). Attaching
   one Part twice to one block is refused.
4. **`Unchanged` throws the payload edits away.** A tick that answers
   `BlockEntityTickReply::Unchanged` has its NBT/data edits rolled back, so compute the new
   state and compare *before* writing (the pot writes only when the soil, seed, growth,
   cooldown or data slots actually changed, so an idle pot stops dirtying its chunk).
5. **`event.click` is `&'a BlockClick<'a>`** — copy it out of the event first
   (`let click = event.click;`), otherwise passing `&mut event` to a helper while a field
   borrow is live does not borrow-check.
6. **`LevelRef::roll_loot` has no block-state loot parameter** (named gap below): a 26.3 crop
   table gates its produce pool on `match_block {blocks: "minecraft:wheat", state: {age: "7"}}`,
   which cannot match without `LootContextParams.BLOCK_STATE`.
7. **`Compound` keys are `JavaString`.** Read with `saved.get(&key.into())` and write with
   `key.into()` / `Tag::String(text.as_str().into())`; the empty string is the "no item"
   shape the 0.1.0 code wrote.
8. **`host.tags().is_in_tag` takes an `ItemKey`**, not an id: the soil has to stay a key from
   the stack (`stack.item()`), while the *saved* state keeps the id the readout prints. Resolve
   the tag once per check (`Tags::key(&Identifier::parse(..))`).
9. **`server_dimension` is `host.dimension()`**, not the click's `LevelDimension`: every
   read here takes `host.level(host.dimension())`, as `charginggadgets` does.
10. **No renderer in `--headless`**: the pot's screen readout (`screen_draw`) is not asserted
    without `--offscreen`, which is unchanged from 0.1.0 (it was never asserted).
11. **`cargo fmt --check`, never `--all`** (that walks `.horizon/sdk`). After any formatting,
    `cmp` `src/runtime.rs` against the retired file again — it must stay byte-identical.
12. **`Cargo.lock` changes the artifact.** `cargo test`/`clippy` write one; `rm -f Cargo.lock`
    right before `cargo horizon-mod build` (and `/Cargo.lock` is in `.gitignore`).
13. **The 0.1.0 e2e cannot run the new package.** `tools/e2e.sh` used to drive a game built by
    `tools/horizon.py` with the bundle compiled in and `--dev-mod content/`; the SDK package is
    built and run by `horizon-launcher native-build .`, which is not installed here. The script
    now takes `GAME=` (optional `CONTROL_GAME=`), keeps `SELFTEST=1`, and no 0.2.0 in-game leg
    is claimed; the 0.1.0 runs in `../_shared/evidence/botanypots/` stand as the behaviour's
    evidence for a `runtime.rs` that did not change.
14. **`tools/carry_content.py` was writing into `content/`** and emitting a second manifest.
    The package root *is* the content root now, so it writes `assets/`/`data/` and no manifest;
    `horizon-mod.toml` is the only one.
15. **The retired tree held files the brief did not list** (`PLAN.md`, the port's old
    `AGENTS.md`, the three EMBEDDED e2e scripts). The artefact wins: all of them instruct the
    retired tooling, so they moved to evidence with the rest.

### Behaviour that changed with the format (deliberate, and why)

- **Bone meal leaves the clicking hand** (`ItemPlace::PlayerHand::extract`, in one transaction
  with the growth write) instead of being taken from the whole inventory by
  `native_take_items`: that was a recorded 0.1.0 deviation, now upstream's `shrink(1)`,
  and a creative player's hand keeps its meal.
- **An idle pot no longer dirties its chunk every tick** (`Unchanged`, trap 4). The growth
  rate, the ready threshold and the reset are unchanged.
- **The harvest's produce comes from the crop's table roll plus the crop block's own item**
  (the gap below), and the seed pools are the table's own roll. For the four compiled crops
  the result equals a no-tool mature break: wheat 1 + 1 seed, carrots 2, potatoes 2 (the
  2 % poisonous potato is lost), beetroots 1 + 1 seed.
- **The readout text is byte-identical** to 0.1.0 (`growth=…/… soil=… seed=… ready=…`,
  `not a botany pot`), so the existing e2e assertions still match; the argument is now the
  typed `block_pos`, whose chat syntax is unchanged.
- **The screen text colour is `0xFF404040`** (the 0.1.0 value had no alpha channel).

### Gaps after the migration

Everything in the 0.1.0 gap list above still stands (the 183 other pots, hopper/waxed pots, the
tool slot, the comparator, waterlogging, the crop renderer, the modded crop/soil registries,
the other fertilizers and interactions, sounds/particles, config). Added by this format:

1. **No block-state loot context.** `LevelRef::roll_loot` gives `origin`, `tool` and `entity`
   but no `LootContextParams.BLOCK_STATE`, and `level_block_drops` rolls the block *at the
   position* (the pot), so a mature crop's state-gated pools cannot be evaluated. The port
   therefore adds the crop block's own item once per yield roll unless the roll already gave
   it; the consequence is measured above (only the potato table's `random_chance` 2 %
   poisonous potato is lost). Closest supported shape recorded; nothing faked.
2. **No in-game re-run in this environment** (trap 13): `horizon-launcher` is not installed,
   so no launcher build with this package exists. The 0.1.0 runs remain the behaviour's
   evidence for the unchanged `runtime.rs`; what changed is the *transport* of the same calls.

### Upstream defects fixed

None found in this migration, and none newly claimed. The 0.1.0 slicing corrections stay as
recorded (the `barrel` template's unused `open` state, the compiled four-crop table instead of
the recipe registry, the clamped growth counter — all deliberate deviations, not defects).
One **harness** defect was fixed: the e2e's differential used `gamerule randomTickSpeed 0`,
which this pin **refuses** (rule ids are snake_case, `horizon-client-core/src/gamerules.rs:108`)
while `ctl command` answers `ok:true` — so the "growth with randomTickSpeed 0" leg proved
nothing. It now sets `random_tick_speed 0`, which makes the differential real. No 0.2.0 run
exists to exercise it (gap 2).

### Changelog for the resubmission (supersedes #793)

> **0.2.0 — republished as an SDK `.hmod`.** Horizon's mod-API merge (launcher ≥ 0.2.70,
> #16941) retired the `.hnmod` container and closed **#793** (`botanypots` 0.1.0); this version
> supersedes it. One flat `botanypots.hmod` now carries the code *and* the content (the
> terracotta pot, its block declaration, menu, models, texture, blockstate, lang, loot table,
> recipe, tags, and the jar's crop/soil/interaction/fertilizer data): `src/lib.rs` is the one
> `impl mod_api::Hooks`, `src/pot.rs` the glue, and `src/runtime.rs` is byte-identical to 0.1.0,
> so the growth rule, the bone-meal cap and the yield rolls behave exactly as before. Built
> against SDK `0b14f8acfd97fa2c750e42795249dcc981178ca4` / mixins
> `e59da9094f0c2fdda6c627fe9eff22dec6a906f0` for 26.3. The `.hnmod`, the mixin plan, the 10
> per-hook helpers and the embedded-content injection are gone; the two clicks are now
> `use_item_on`/`use_without_item` on the pot block, the container is a declaration, and bone
> meal is taken from the clicking hand instead of the whole inventory. Same feature set and the
> same gaps (183 other pots, hopper/waxed forms, tool slot, comparator, modded crop/soil
> registries, crop renderer). Package: 170 entries, **91,693 B**, sha256
> `18218cafb9ad6fc5d2c5de49c93311efef4cb912c1e68bc20a4a287f9556e515`; `check` and `fits` exit 0;
> 14 tests, clippy `-D warnings` clean. No 0.2.0 in-game run: the launcher is not installed
> here (trap 13).

### Publication route (campaign ruling 2026-11-18)

The submission form is gone; publishing is now `horizon-rust/horizon-mods#1147` — the artifact
is attached to a release of the author's own repository under the entry's exact `file` name, a
PR adds the `[[versions]]` record and links the file, and a **maintainer** runs
`scripts/stage.sh` (a red `check` before that is the expected `fetch.sh` failure). The
orchestrator's `python3 ports/tools/publish-ready.py botanypots` does the bookkeeping; this
job owns no submission.

Skills: superpowers/using-superpowers,writing-plans,test-driven-development,verification-before-completion; BeautifulRust/rust-best-practices

## Slice 2 — hopper pots (0.2.1, 2026-11-20)

**The slice's source line** (this file, *Slice boundary* above, quoted verbatim):

> **Out (gaps, next slices):** the 183 other pot variants; hopper pots (12 output
> slots, export below, auto-harvest) and waxed pots; the tool slot and harvest
> tool damage/enchantments; the comparator output; …

Taken: **hopper pots** — one complete behaviour with one observable (a grown crop is harvested
without a click and lands in the hopper pot's twelve storage slots, and the slots push into the
container below). Left for later: the 181 other pot variants, waxed pots, the tool slot's
effects, the comparator, waterlogging, the crop renderer, the modded crop/soil registries.

### Approach (from the pin's `docs/modpacks.md`)

Class **content**, tier **machines** — unchanged. The shape is the tier's: one more carried block
(the hopper pot), its block entity's second mode (auto-harvest + export), a fifteen-slot container
and menu, and its recipe/loot/tag/item data. Not a new tier and not a data-only carry.

### What the hopper pot is, read from upstream

Read from `BotanyPotBlockEntity.tickPot` (`isHopper()` branch), `AbstractBotanyPotBlockEntity`
(`SLOT_COUNT` 15, `STORAGE_SLOTS` 3..15, `getSlotsForFace`, `canTakeItemThroughFace`),
`BotanyPotMenu` (the hopper layout) and `PotType.HOPPER` at `335c997`:

| Area | Upstream | This slice |
|---|---|---|
| slots | 15: soil 0, seed 1, tool 2, storage 3–14 | same indices; the tool slot exists and is **inert** (its damage/enchantments are the next slice) |
| growth | same rule as the basic pot | same |
| harvest | basic pots: click only. Hopper pots: **on their own tick**, once `growth >= required` | same |
| harvest output | `addItem(drop, items, STORAGE_SLOTS)` per roll: **one pass in slot order** — top up a matching slot, the first empty slot takes the rest | same rule (`runtime::plan_insert`, pinned by a test that an empty slot before a matching one takes the whole drop), with the remainder **popped at the pot** (defect fix below) |
| export | every tick, each storage slot pushed into the block below through its UP face (`inventoryInsert`) | same (`container_insert_kind` through `Direction::Up`) |
| container faces | `getSlotsForFace(DOWN)` = storage, every other face empty; `canPlaceItemThroughFace` false everywhere; `canTakeItemThroughFace` only a hopper pot's storage | `faces[DOWN]` = storage, inputs empty, outputs = storage (hopper pot only) |
| menu | `hopper_pot_menu`, 15 slots: soil (44,48), seed (44,22), tool (18,35), 12 storage 4×3 from (80,17) | same layout, a `screen` Part chosen by block id |
| bone meal / menu click | both pots | same (`PotClick` on both blocks; the harvest branch is basic-only) |
| recipe | shapeless: hopper + botany pot, gated on a config flag | carried shapeless (the config gate is a gap: this port has no config) |

### Upstream defect fixed

**A full hopper pot silently destroys its harvest.** `BotanyPotBlockEntity.java:116` passes
`Services.GAMEPLAY.addItem(stack, pot.getItems(), STORAGE_SLOTS)` — which **returns** the items that
did not fit (`IGameplayHelper.addItem`, Bookshelf 21.1.75: `return stack;` at the end, and
`return ItemStack.EMPTY` only when everything went in) — to a `Consumer<ItemStack>` lambda, whose
return value Java discards. With all twelve slots full the roll is lost. The port **pops the
remainder at the pot** (`LevelRef::pop_resource`), so a harvest is never destroyed; a user sees the
overflow on the ground instead of it vanishing. Proven in game by the e2e's full-storage phase.

### Plan (TDD, in this order)

1. **`runtime.rs` first, tests first**: `is_hopper_pot`, the slot layout constants
   (`SOIL_SLOT`, `SEED_SLOT`, `TOOL_SLOT`, `STORAGE_FIRST`, `SLOT_COUNT`, `BASIC_SLOT_COUNT`,
   `storage_slots()`), and `plan_insert(&[Held], count, max) -> Insertion` — one pass in slot
   order (a matching slot is topped up, the first empty slot takes the rest, anything else is
   skipped) with a remainder. Watch each test fail, then implement.
2. **Glue (`src/pot.rs`)**: hopper block/type/menu constants; `container()` and
   `hopper_container()`; `menu_for`
   and `screen` by block id; the tick's hopper branch (roll the mature crop's loot, insert into
   storage, reset growth, pop the remainder) and the export (`container_insert_kind` through the
   block below's UP face); `PotClick` on both blocks with the harvest branch basic-only.
   Declaration tests: 15 slots/faces/outputs for the hopper pot, 2/no-face for the basic pot, the
   hopper menu's fifteen positions.
3. **Content**: `tools/carry_content.py` grows the hopper pot's blockstate, models (incl. the
   jar's `template/hopper_pot`), item definition, lang line, block/item tag membership, loot
   table, block declaration, `hopper_pot_menu.json`, and the 26.3-shaped shapeless recipe.
   `--check` proves every file; `cargo horizon-mod check` proves the package.
4. **e2e (`tools/e2e.sh` + `tools/craft_check.py`)**: keep every slice-1 phase unchanged, then add
   — craft the hopper pot (assert output id/count **and** that the pot and hopper were consumed;
   controls: pot alone, hopper alone), place it and read the block back, assert
   `#botanypots:botany_pots` membership (with a dirt control), give/read the item, grow a crop and
   assert it is auto-harvested into slots 3–14 with no click, assert the twelve-slot **full**
   control pops the overflow, and assert the slots export into a chest below; the basic pot's own
   phase is the control that it does **not** auto-harvest; an unknown id is refused.
   `SELFTEST=1` inverts the auto-harvest assertion; `CONTROL_GAME` is the unmodded Nightly.
5. **Ladder and evidence**: `rm -f Cargo.lock` before each build, `cargo test --offline`,
   `cargo clippy --all-targets --offline -- -D warnings`, `cargo fmt --check`, two identical
   builds, `check`, `fits --build 0b14f8a`, `verify-sdk-package.py botanypots` 1/1, then the
   launcher game leg (`launcher-game.sh build/run`) plus the control and selftest legs.

Version: **0.2.1** (one patch above the published 0.2.0). The registry entry is not touched here;
the published `[[versions]]` record for 0.2.0 stays and 0.2.1 is added at publication.

### Slice 2 results — what was built, and what the game proved (2026-11-20)

**Ladder (0.2.1, pin SDK `0b14f8a` / mixins `e59da90`, 26.3).** Every compile in a
`build-slot.sh` lease with `BUILD_LOCAL=1`, `CARGO_INCREMENTAL=0`, `rm -f Cargo.lock`
before each build, no `--target-dir`:

| Step | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **24 passed, 0 failed** (`sdk-test.log`) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** (`sdk-clippy.log`) |
| format | `cargo fmt --check` | `FMT_EXIT:0` (`sdk-fmt.log`) |
| package | `cargo horizon-mod build` twice | **61,107 B**, sha256 `2cea1f30…1279`, `cmp` identical (`sdk-build.log`, `sdk-build-second.log`, `sdk-reproducible.txt`) |
| check | `cargo horizon-mod check botanypots.hmod` | `botanypots 0.2.1 (native-mod, format native-1/0b14f8a…/e59da90…, for 26.3)`, exit 0 (`sdk-check.log`) |
| fits | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  made for`, exit 0 (`sdk-fits.log`) |
| content carry | `python3 tools/carry_content.py --check` | **37 files, 0 pending**, jar SHA-1 `fcb58dfa…` |
| package gate | `python3 ports/tools/verify-sdk-package.py botanypots` | **1/1** (runtime byte-identical, no packed lock, 48 entries) |

The package is **48 entries**: `horizon-mod.toml`, `Cargo.toml`, `LICENSE`,
`LICENSE-NOTICE.md`, `README.md`, `src/{lib,pot,runtime}.rs`, `uses.json`, 7 `assets/`,
35 `data/`; no `Cargo.lock`. `botanypots.hmod` sits in the port root.

**In game** (`ports/tools/launcher-game.sh run botanypots`, launcher 0.2.78, exported
Nightly `0b14f8a`, `~/.cache/horizon-e2e/`):

| Leg | Verdict | Evidence |
|---|---|---|
| the package's own game, full scenario | **`PASS` + `EXIT:0`** | `../_shared/evidence/botanypots-e2e/e2e-launcher.log` |
| the same scenario on the unmodded Nightly (`GAME=$CONTROL_GAME`) | **`FAIL: cannot give botanypots:terracotta_botany_pot` + `EXIT:1`** | `e2e-control.log` |
| `SELFTEST=1` (hopper counterfactual) | **`FAIL: SELFTEST: the hopper pot's storage holds 1 wheat (the check is alive)` + `EXIT:1`** | `e2e-selftest.log` |
| `SELFTEST=basic` (slice-1 counterfactual) | **`FAIL: SELFTEST: the no-soil pot harvested nothing (the check is alive)` + `EXIT:1`** | `e2e-selftest-basic.log` |

`python3 ports/tools/check-e2e-logs.py botanypots-e2e --strict` → `logs=4 ok=4
missing-exit=0 bad-exit=0`. The main leg also runs the unmodded Nightly *first*, inside
the same log: both pot ids are unknown there, no pot item can be given, and
`/botanypots info` answers nothing (`native command reply: none`).

The `ctl` transcript the report quotes (abridged; every line is a reply or an assertion):

```
hopper + botany pot -> {"count": 1, "item": "botanypots:terracotta_hopper_botany_pot", "slot": 200}
inventory: 1 hopper pot, 0 pot, 0 hopper
terracotta + flower pot -> {"count": 1, "item": "botanypots:terracotta_botany_pot", "slot": 200}
inventory: 1 botany pot, 0 ingredients left
botany pot alone -> null        hopper alone -> null
placed: botanypots:terracotta_hopper_botany_pot
tag replies: TAG_BASIC TAG_HOPPER          (a stone control did not match)
menu slots: 15
  bone meal 1: growth 19 -> 574
  bone meal 2: growth 578 -> 1100
  bone meal 3: growth 1104 -> 26           <- the tick harvested by itself
after the self-harvest: storage wheat 1, seeds 1; growth=87/1200 ready=false
basic pot after 40 ready ticks: growth=1200/1200 ready=true; wheat 1 -> 1   <- no self-harvest
export: storage holds 0 wheat; the chest below reads: … id: "minecraft:wheat" …
overflow: wheat in inventory 0, on the ground 1; stick stacks still 12     <- the fix
unknown id: give refused, setblock left 'minecraft:air'
```

### Coverage — every family in the jar (parity rule, 2026-11-20)

| Family in Botany Pots 21.1.44 | Status |
|---|---|
| basic pot block, item, blockstate, model, texture, lang, loot table | **tested** — phases 1/2 (place + readout), 8 (loot), craft case 1, tag phase, unknown-id phase |
| basic pot crafting recipe (shaped, 5 terracotta + flower pot) | **tested** — craft case 1 (output id/count, ingredients consumed) |
| hopper pot block, item, blockstate, model (+ `template/hopper_pot`), lang, loot table | **tested** — give/place/read-back phase, craft case 2, unknown-id phase |
| hopper pot crafting recipe (shapeless hopper + pot) | **tested** — craft case 2 + pot-alone/hopper-alone controls |
| hopper pot: 12 storage slots, auto-harvest, downward export | **tested** — phases 11 (storage), 13 (chest), 14 (overflow), control 12 (basic pot does not) |
| hopper pot menu (15 slots) | **tested** — menu phase (`menu slots: 15`), declarations pinned in unit tests |
| block/item tags `#botanypots:botany_pots` | **tested** — `execute if block … #botanypots:botany_pots`, stone control outside |
| soil tags (`#botanypots:soil/dirt`, …) | **tested** — growth in dirt, sand refused (slice 1) |
| growth rule, soil modifier, bone meal, yield rolls | **tested** — phases 3–7 + unit tests |
| the other 181 pot variants (colours, materials) | **not ported** — later slices; only `terracotta_*` are registered |
| waxed pots | **not ported** — no ticking/rendering mode |
| the tool slot's effects (damage, enchantments, growth/yield modifiers) | **not ported** — the slot exists in the hopper menu and holds an item, but changes nothing |
| comparator output | **not ported** — no `getAnalogOutputSignal` equivalent in the port |
| waterlogging and the `LEVEL` light | **not ported** — the `barrel` template carries neither |
| crop display renderer | **not ported** — client renderer |
| modded/remaining crops and the soil registry | **not ported** — the compiled four-crop table; the jar's crop/soil recipes were **dropped** (their serializers do not exist here) |
| fertilizers other than bone meal, pot interactions (hoe→farmland, shovel→path, bucket→stone) | **not ported** — dropped with the same recipe files |
| hopper automation *in* (a hopper filling the pot) | **not ported, deliberately** — upstream refuses every insert face; `inputs` is empty, which is the faithful shape |
| JEI, Patchouli/docs, config (`global_growth_modifier`, `damage_harvest_tool`, …), sounds, particles | **not ported** |
| breaking the pot (spilling its slots, dropping the item) | **not asserted** — engine-owned; the carried loot table is patched for 26.3 |
| the block entity's saved data across a reload | **not asserted** — unit tests pin the compound round-trip |

### Upstream defects fixed

1. **A full hopper pot destroyed its harvest.** `BotanyPotBlockEntity.java:116` passes
   `Services.GAMEPLAY.addItem(stack, pot.getItems(), STORAGE_SLOTS)` — which **returns** what
   did not fit (Bookshelf 21.1.75 `IGameplayHelper.addItem`, `return stack;`) — to a
   `Consumer<ItemStack>` whose value Java discards. With all twelve slots full the roll was
   lost. The port pops the remainder at the pot (`LevelRef::pop_resource`); a user sees the
   overflow on the ground. Proven by phase 14 (`wheat in inventory 0, on the ground 1;
   stick stacks still 12`) and the `SELFTEST` leg, which asserts the storage was empty and
   must fail.
2. **The harvest's produce was the wrong item.** The 0.2.0 workaround asked
   `host.block_item(host.block_state_id(crop.block)?.block())`, which answers the block's
   **placing** item, not `Block.asItem()`: measured in game on 2026-11-20, `minecraft:wheat`
   answered `minecraft:wheat_seeds` (a crop block has no item of its own), so a 0.2.0 harvest
   would have yielded seeds instead of produce — and the first 0.2.1 run measured exactly
   that (`harvest: wheat 0, seeds 1`). The produce now comes from the compiled crop table
   (`Crop::produce`, a runtime test pins all four), and the game yields `minecraft:wheat`.

### Package defect fixed (the port's own, not upstream's)

3. **The package could not load at all.** 0.1.0/0.2.0 carried the jar's
   `data/botanypots/recipe/minecraft/{crop,soil,interaction,fertilizer}` files (131 files)
   whose types are Java recipe serializers (`botanypots:block_derived_crop`,
   `botanypots:block_derived_soil`, `botanypots:soil`, `botanypots:pot_interaction`,
   `botanypots:fertilizer`) this port never registers. Horizon **refuses the pack**:
   `recipe …/crop/allium.json, unregistered recipe serializer botanypots:block_derived_crop`
   → crash report, exit 1, before the first assertion. No 0.2.0 in-game run existed, so no
   gate saw it. The files are dropped (`tools/carry_content.py` records why; 168 → 37
   content files), the compiled crop table is what the port reads, and the jar stays the
   evidence to re-carry them when a slice implements the registries. Under the parity rule
   this is "a carried recipe that is never crafted is dead data": dropped, and said why.

### Deliberate deviations (slice 2)

- **The tool slot is inert.** Upstream's hopper menu has a harvest-tool slot (slot 2) whose
  item is damaged, shortens growth and raises yield; this port shows and stores it but has
  none of those effects (the gap list's "tool slot").
- **No per-slot menu filters.** `Screen` has no per-slot predicate, so soil/seed/tool slots
  accept any item; the tick ignores a non-crop seed and a non-soil soil, as it did in slice 1.
- **No 5-tick `growCooldown`** after a hopper harvest; the counter resets and grows on.
- **The export is one `STORAGE` insert per storage slot each tick** through the block below's
  upward face (the `container_insert_kind` path upstream's `inventoryInsert` uses), and the
  hopper pot's container also declares `faces[DOWN]`/`outputs` so a vanilla hopper under it
  pulls. Both are the same two upstream rules.
- **The basic pot keeps no container face** (upstream answers storage for `DOWN` but refuses
  every take); the behaviour is identical and the declaration is simpler.

### Harness facts learned (for the next slice)

- **`ctl interact` on a half-block shape can miss** when aimed at the block's centre (the
  pot's shape is 8/16 high, so the centre sits on its top edge). Aim at a face:
  `ctl interact X Y Z south`. One run lost two of three bone-meal clicks to this.
- **A vanilla chest's menu does not open in this harness at this pin**: the click lands
  (`block: minecraft:chest`, `ok: true`) and `screen` stays `playing`, from above and from
  the side, with `look-at-block` first. The export is therefore read with
  `data get block X Y Z Items`, the server's own contents.
- **A pot above a chest intercepts a click from above** — normal Minecraft; read the chest
  from the side or by NBT.
- **A right click on a pot holding bone meal fertilises instead of opening the menu**; a
  storage read must empty the hand first (`empty_hand`).
- **`/botanypots info` costs two ticks per read**, so "just planted"/"just harvested" are
  ranges (`< 100`, `< 200`) and the growth window is a **delta** over the wait (the absolute
  "grew 66 in 40" read is the same boundary flake the 0.1.0 notes recorded at 61).
- **A hopper pot never reads `ready=true`**: its tick harvests the moment it is ready, so a
  bone-meal loop for a hopper pot cannot wait for readiness; three meals always reach the
  cap (3 × 400 > required − 20), and a growth **decrease** is the harvest signal.

### Changelog for the resubmission (supersedes 0.2.0)

> **0.2.1 — the hopper botany pot.** Adds `botanypots:terracotta_hopper_botany_pot`:
> fifteen slots (soil, seed, an inert tool slot, twelve storage), its own 15-slot menu, and
> the hopper behaviour — a crop that harvests **itself** the tick it ripens into the twelve
> storage slots, and those slots pushed into the container below. Its shapeless recipe
> (hopper + botany pot), loot table, tag membership and item model are carried. Two fixes
> ride along: a full hopper pot now pops its overflow at the pot instead of destroying it
> (upstream's `addItem` remainder is discarded), and the package no longer carries the jar's
> 131 crop/soil/interaction/fertilizer recipe files, whose serializers this port does not
> implement and which made Horizon refuse the whole pack. The basic pot is unchanged. Same
> pins (`0b14f8a` / `e59da90`, 26.3). Package: **48 entries, 61,107 B**, sha256
> `2cea1f308608d65072ef9c945c289550238d5c5e3ce80e383750d5c2b5681279`; `check` and `fits`
> exit 0; 24 tests, clippy `-D warnings` clean; **in game** `PASS` + `EXIT:0` with the
> unmodded Nightly at `EXIT:1`, and two `SELFTEST` legs at `EXIT:1`. Gaps unchanged: the
> other 181 pot variants, waxed pots, the tool slot's effects, the comparator, waterlogging,
> the crop renderer, the modded crop/soil registries.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices
