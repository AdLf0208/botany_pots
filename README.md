# Botany Pots — Horizon port

![icon](icon.png)

A Horizon port of Botany Pots (LGPL-2.1-only): the basic botany pot — soil and seed slots, growth, bone meal and harvest.

**Status: slice 1 — partial.** This repository implements the items listed under
*What works*; the rest of Botany Pots is listed under *Not yet ported* and is
welcome as a contribution.

## What works

- `botanypots:terracotta_botany_pot` with a soil slot and a seed slot, its carried blockstate, block/item models, textures and loot table, and the jar's crop/soil/interaction/fertilizer data (160 content files).
- Growth on the block entity's own server tick: 1,200 ticks for plain dirt, 1,090 for farmland (+0.10); readiness is shown by the menu and `/botanypots info`.
- Harvest by right-click when ready, rolling the mature crop block's real loot table once per yield roll and resetting growth; the seed stays in the pot.
- Bone meal adds 400–600 growth (capped at required − 20) with the upstream 20-tick cooldown; creative does not consume it.
- A two-slot content menu with a progress readout, and `/botanypots info <x> <y> <z>`.
- Four supported crops from the jar's own files: wheat, carrots, potatoes and beetroots.

## Install

1. Take `botanypots.hnmod` (the native bundle) and `content/botanypots.hmod`
   (the content package) from this repository, or from the
   [`botanypots-21.1.44`](https://github.com/AdLf0208/botanypots/releases/tag/botanypots-21.1.44)
   release.
2. Put the native bundle in the game folder's `horizon-native-mods` folder — the
   game folder is the one holding `options.txt`. Install the content package the
   same way you install any Horizon content mod.
3. Native mods are always on once installed; the first install shows a trust
   notice, and the launcher builds the mod for your game.

To try it without installing, start the game with `--dev-mod` pointing at both
files.

## Build from source

This is a native mod: a carried content half plus a Rust runtime and typed
mixins. The build needs the pinned Horizon and horizon-mixins checkouts; the
exact revisions are in `compatibility.json`.

```sh
cargo test --locked --offline                        # the pure runtime rules
python3 tools/horizon.py stage --horizon <horizon-checkout>
python3 tools/horizon.py check --horizon <horizon-checkout>
python3 tools/horizon.py test  --horizon <horizon-checkout>
python3 tools/horizon.py build --horizon <horizon-checkout>
```

`tools/e2e.sh` is the in-game harness. It expects a campaign checkout
(`$CAMPAIGN_ROOT`), the shared pins and the prepared 26.3 resources
(`$HORIZON_RES`, default `.local/horizon-client/26.3`).

The campaign's evidence for this slice — the runtime tests, the staged check,
the embedded tests, the fast build and a fail-capable in-game run — is kept
outside this repository.

## Compatibility

| | |
|---|---|
| Horizon | `1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9` (`game.rs` `64813cf4…`) |
| horizon-mixins | `5a64af938ec86b00d53d16a408aabc0038fb3e57` (schema 6) |
| Minecraft: Java Edition | 26.3 |
| Content API | 0.2 |

Local-only features and engine gaps are listed under *Not yet ported*; a hook
the pin does not offer is not guessed at.

## Credits

A port of [Botany Pots](https://github.com/Darkhax-Minecraft/BotanyPots) 21.1.44 by
Darkhax, licensed **LGPL-2.1-only**. The
original copyright and licence notices are reproduced in [LICENSE](LICENSE);
[LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where every notice was read
from. Botany Pots is not affiliated with Horizon and has not endorsed this
port.

The Rust runtime, the Horizon declarations and the build/verification tooling
are the work of AdLf0208.

## Licence

**LGPL-2.1-only** — the original's licence, and the licence of this
port. The complete corresponding source is this repository: `mixins/` (the
runtime and hook helpers), `content/` (the carried data), `Cargo.toml` and
`Cargo.lock`, and `tools/` (the build and harness scripts). Redistribution and
modification are allowed under the same licence, provided the licence and this
source travel with every copy. See [LICENSE](LICENSE).

No Mojang file is included. The carried files are the mod's own assets and
data; `data/minecraft/tags/…` files only add this mod's ids to vanilla tags.

## Contributing / help wanted

This is a deliberately partial port: the gap list above is the roadmap. If you
want to continue it, the clean seams are the missing machines/blocks, the GUIs
and side configuration, and the renderers. Open an issue on this repository
with the slice you want to take; keep the same clean-room rule (behaviour from
the upstream mod and its data, no translated Java) and the same licence.
