# Licence notice — Botany Pots

This port carries the original mod's assets and data and rewrites its behaviour
in Rust. The original licence and copyright notices are reproduced verbatim in
[LICENSE](LICENSE).

## Where the licence was read

| | |
|---|---|
| Pack jar | `botanypots-neoforge-1.21.1-21.1.44.jar` (1,068,816 B, SHA-256 `45b23ac195511f724f62ab5f0c2d7a1c2c2403ff324a7403a1142e28a7d65edd`) |
| Declared licence | `LGPL v2.1` in `META-INF/neoforge.mods.toml` |
| Licence text | the jar's own `license_botanypots.txt` (26,466 B, byte-identical to the LGPL-2.1 text) (26,466 B) |
| SPDX identifier | `LGPL-2.1-only` |
| Copyright line | `Copyright (c) Darkhax and Botany Pots contributors` |

The jar also ships `license_botanypots.txt`. The jar names the author(s) `Darkhax` but
carries no separate project copyright line, so the copyright line above uses
that author list; replace it with the upstream `LICENSE` copyright statement if
one is added later.

## The port

- Original: Botany Pots 21.1.44 by
  Darkhax — LGPL-2.1-only
  (https://github.com/Darkhax-Minecraft/BotanyPots).
- Port to Horizon by AdLf0208: the Rust runtime, the Horizon declarations and the
  build/verification tooling in this repository.
- This repository is the complete corresponding source: the licence requires
  that it travels with every copy and with every modified version.
- No Mojang file is included. The carried files are the mod's own assets and
  data; `data/minecraft/tags/…` files only add this mod's ids to vanilla tags.
