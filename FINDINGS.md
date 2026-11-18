# Botany Pots — upstream analysis (slice 1)

Analysis aid only: the port is a clean-room Rust rewrite. Read for behaviour,
never translated.

## The exact ATM10 file

`botanypots-neoforge-1.21.1-21.1.44.jar` — the pack's Crash Assistant export
(`https://raw.githubusercontent.com/AllTheMods/ATM-10/main/config/crash_assistant/modlist.json`,
entry `modId: botanypots`) lists:

```json
{"jarName": "botanypots-neoforge-1.21.1-21.1.44.jar",
 "modId": "botanypots",
 "name": "BotanyPots",
 "version": "21.1.44",
 "curseForgeHash": 869204191,
 "modrinthHash": "fcb58dfa5f52819c85da40025fa50d0ddccbbb47"}
```

Fetched from Modrinth by that SHA-1 (`/v2/version_file/fcb58dfa…` → version
`RjHfHgSn`): SHA-1 matches, SHA-256
`45b23ac195511f724f62ab5f0c2d7a1c2c2403ff324a7403a1142e28a7d65edd`, 1,068,816 B,
2,449 entries. `META-INF/neoforge.mods.toml` → licence `LGPL v2.1`
(the jar also carries `license_botanypots.txt`). Full provenance:
`../_shared/carry-work/botanypots/SOURCE.md`.

## Upstream source (behaviour only)

- Repo: <https://github.com/Darkhax-Minecraft/BotanyPots>, branch `1.21.1`
- Commit: `335c997` (2026-06-13, the day of the jar build; `gradle.properties`
  version `21.1`, mod version 21.1.44)
- Clone: `ports/_shared/upstream/botanypots` (shallow, deleted after this file
  was written).

Read for behaviour: `common/impl/block/BotanyPotBlock.java`,
`common/impl/block/entity/{AbstractBotanyPotBlockEntity,BotanyPotBlockEntity}.java`,
`common/impl/block/menu/BotanyPotMenu.java`, `common/impl/Helpers.java`,
`common/impl/data/recipe/{crop/BasicCrop,BlockDerivedCrop,soil/BasicSoil,
BlockDerivedSoil,interaction/BasicPotInteraction,fertilizer/BasicFertilizer}.java`,
`common/impl/data/{itemdrops/BlockStateDrops,growthamount/RangedGrowthAmount}.java`,
`common/impl/config/Gameplay.java`, plus the jar's own `assets/` and `data/`.

## Behaviour extracted (slice 1 scope)

| Area | Upstream |
|---|---|
| slots | 15: `SOIL_SLOT 0`, `SEED_SLOT 1`, `TOOL_SLOT 2`, storage `3..15`; soil/seed/tool are player-only (no hopper insert: `canPlaceItemThroughFace` is always false) |
| menu | basic pot: 2 slots (soil at 80,48; seed at 80,22), data = block pos; hopper pot adds tool + 4×3 output |
| pot types | BASIC (harvest by right-click), HOPPER (auto-harvest into storage, exports below), WAXED (never grows: growth frozen at `Float.MAX_VALUE`) |
| soil | a data recipe per soil item (`botanypots:block_derived_soil`, input = the block's item). Dirt family default 0 growth modifier; `minecraft:farmland` (and sculk catalyst) `+0.10`. Soils also carry a light level and a growth/yield modifier |
| crop | a data recipe per seed (`botanypots:block_derived_crop`): block, optional seed (derived from the crop block for vanilla crops), soil ingredient (default `#botanypots:soil/dirt`), `grow_time` default **1200** ticks, drops (default: the block's loot table rolled at the mature state), base yield 1.0, yield scale 1.0 |
| growth | every server tick of the block entity, when `crop.isGrowthSustained` (the pot's soil item is in the crop's soil ingredient): `growth_time += 1`; harvest is ready when `growth_time >= floor(cropTime / growthModifier)`; `growthModifier = 1 (global config) + soil modifier + tool efficiency modifier + pot modifier` |
| harvest (basic) | right-click with a basic pot whose growth is ready: reset growth and `Block.popResource` each rolled drop at the pot; the pot keeps its soil and seed |
| harvest (hopper) | at the ready tick the crop is harvested into the 12 storage slots (`getLootRolls` times), then a 5-tick grow cooldown; storage exports into the block below every tick when that block is not air |
| yield rolls | `determineRollCount(yield)`: `floor(yield)` guaranteed rolls plus one more with probability `yield % 1` |
| bone meal | a fertilizer recipe (`botanypots:fertilizer`, held `bone_meal`, ranged growth 400..600): `growth_time = min(growth_time + rand, required - 20)`, 20-tick cooldown, one meal consumed outside creative; only when `required > 20` |
| interaction | right-click: harvest when ready; else a fertilizer recipe; else a pot-interaction recipe (hoe→farmland, shovel→dirt path, buckets→stone/obsidian); else open the menu |
| comparator | `comparator_level = ceil(14 * growth/required)` while growing, 15 when ready, 0 when reset |
| waterlogging | `SimpleWaterloggedBlock`; the pot holds water |
| block | `BaseEntityBlock`, `SHAPE = box(2,0,2,14,8,14)`, light = the `LEVEL` state property, `noOcclusion`, hardness 1.25 / resistance 4.2, facing = opposite of the placer's nearest looking direction, default sound (stone) |
| break | `Containers.dropContentsOnDestroy` drops the slots, then the block's own loot table drops the pot |
| growth in the dark | a pot crop does **not** check light: growth is the block entity's own tick, not a random tick |

## What slice 1 ports (and why this shape)

- **The basic pot block** `botanypots:terracotta_botany_pot` (the jar's plain
  "Botany Pot"), on the `minecraft:barrel` template so its use path opens the
  content menu (the same template choice Functional Storage proved).
- **Two container slots** (soil 0, seed 1) and a two-slot content menu
  (`botanypots:basic_pot_menu`, 2 data slots: growth and required ticks) with a
  `native_screen` layout and a text progress readout.
- **Four vanilla crops**, the jar's own `data/botanypots/recipe/minecraft/crop/`
  entries: wheat, carrots, potatoes, beetroots — seed item, crop block, mature
  `age=7`, `grow_time 1200`, soil `#botanypots:soil/dirt`, base yield 1.
- **Harvest by right-click**: the real block loot table of the mature crop state
  (`Game::block_loot_at`), rolled once per yield roll, popped at the pot
  (`Game::pop_resource`), then growth reset. This matches upstream's
  `BlockStateDrops` (block loot table at the harvest state).
- **Bone meal** (400..600, 20-tick cooldown, capped at `required - 20`), the
  faithful way to force growth in a test.
- **Soil growth modifier**: farmland `+0.10`, every other dirt-family soil 0
  (the only `growth_modifier` values in the jar's vanilla soil recipes).
- **The pot's carried assets**: blockstate, block model, the shared
  `template/pot` model, the item model, `terracotta_pot_top.png`, the soil item
  tags, the pot tags (filtered to the one registered block), the block's loot
  table (re-spelled for 26.3), the crafting recipe (re-spelled), the crop/soil/
  interaction/fertilizer data files of the vanilla namespace, lang and one
  creative tab.

## Deliberate differences and gaps (recorded, not invented)

- **One pot variant**: `terracotta_botany_pot` only. The other 183 (coloured,
  hopper, waxed) are content carried only when their behaviour exists; their
  models/textures stay in the jar.
- **No tool slot**: the tool's `increase_pot_growth` enchantment and the growth
  attribute are not read, so the growth modifier is `1 + soil`. The harvest
  tool's durability is untouched.
- **Hopper/waxed behaviour is not implemented** (no auto-harvest, no storage
  slots, no export below, no frozen waxed growth): slice 1 is the plain pot.
- **No comparator output** yet: the block entity does not maintain
  `comparator_level`, so a comparator beside the pot reads 0.
- **No waterlogging** (the template has no `waterlogged` state) and no `LEVEL`
  light property; the pot emits no light.
- **The crop is not drawn** in the pot: no `native_block_entity_submit`
  renderer; the pot shows its own model only.
- **Crops are a compiled table of four**, not the JSON crop registry: the
  modded crops, the remaining ~70 vanilla crops, per-crop `grow_time`/`yield`
  overrides and the pot predicate are not read. The jar's data files are
  carried so the next slice can parse them.
- **Only the dirt-family soil tag is honoured** (plus farmland's modifier);
  sand, nether/end/sculk water buckets etc. have no growth entry (matching
  upstream: a crop whose soil ingredient does not accept the item does not
  grow).
- **Bone meal is taken from the inventory** (`native_take_items`) rather than
  shrunk in the exact hand; creative does not consume it.
- **The pot's menu cannot be opened by a non-Horizon client** (content menus
  are Horizon-only, as the pin documents).
- **No sound or particles** on harvest/bone meal.
