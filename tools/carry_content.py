#!/usr/bin/env python3
"""Carry the botany-pot slice of Botany Pots 21.1.44 into the package root (assets/, data/).

Both pots this port ships — the basic `terracotta_botany_pot` and the
`terracotta_hopper_botany_pot` — are carried from the jar, with the shared
`template/pot` and the hopper pot's own `template/hopper_pot` model. The jar is
the ATM10 one, resolved by SHA-1 from the pack's Crash Assistant export (see
../../_shared/carry-work/botanypots/SOURCE.md). Asset bytes are copied verbatim;
the few data files 26.3 spells differently, or that name the blocks this port
registers, are written from the jar's own values.

Run: python3 tools/carry_content.py [--jar PATH] [--check]
  --check  compare the files on disk with what the carry would write, exit 1
           on a difference (no writes).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JAR = (
    ROOT.parent / "_shared/carry-work/botanypots"
    / "botanypots-neoforge-1.21.1-21.1.44.jar"
)
JAR_SHA1 = "fcb58dfa5f52819c85da40025fa50d0ddccbbb47"
MOD = "botanypots"
POT = "terracotta_botany_pot"
HOPPER = "terracotta_hopper_botany_pot"

# Bytes copied unchanged from the jar, by directory.
#
# The jar's `data/botanypots/recipe/minecraft/{crop,soil,interaction,fertilizer}`
# files are deliberately **not** carried: their types (`botanypots:block_derived_crop`,
# `botanypots:block_derived_soil`, `botanypots:soil`, `botanypots:pot_interaction`,
# `botanypots:fertilizer`) are Java recipe serializers this port does not implement, and
# Horizon refuses to load a pack holding one — the 0.2.1 e2e crashed at content load with
# `unregistered recipe serializer botanypots:block_derived_crop`. They are dead data here
# until a slice implements the crop/soil registries; the compiled four-crop table in
# `src/runtime.rs` is what this port reads. The jar stays as the evidence to re-carry them.
VERBATIM_DIRS = [
    "data/botanypots/tags/item/soil",
]
VERBATIM_FILES = [
    f"assets/{MOD}/blockstates/{POT}.json",
    f"assets/{MOD}/blockstates/{HOPPER}.json",
    f"assets/{MOD}/models/block/{POT}.json",
    f"assets/{MOD}/models/block/{HOPPER}.json",
    f"assets/{MOD}/models/block/template/pot.json",
    f"assets/{MOD}/models/block/template/hopper_pot.json",
    f"assets/{MOD}/models/item/{POT}.json",
    f"assets/{MOD}/models/item/{HOPPER}.json",
    f"assets/{MOD}/textures/block/terracotta_pot_top.png",
    f"data/{MOD}/tags/item/harvest_items.json",
    f"data/{MOD}/tags/item/crop_generator_ignores.json",
]

BLOCK_DECL = {
    "template": "minecraft:barrel",
    "properties": {
        "hardness": 1.25,
        "explosion_resistance": 4.2,
        "requires_tool": False,
        "sounds": "minecraft:terracotta",
        "occludes": False,
    },
    # Block.box(2, 0, 2, 14, 8, 14): the pot is 12 wide and 8 tall. The hopper
    # pot's model hangs its hopper below, but the collision box is the pot's.
    "shapes": {"default": [[0.125, 0.0, 0.125, 0.875, 0.5, 0.875]]},
    "collision_shapes": {"default": [[0.125, 0.0, 0.125, 0.875, 0.5, 0.875]]},
}

# `BotanyPotMenu`: the basic pot shows soil and seed, the hopper pot fifteen slots
# (soil, seed, tool, 4x3 storage) with the same two data slots.
MENU_DECL = {"slots": 2, "data_slots": 2}
HOPPER_MENU_DECL = {"slots": 15, "data_slots": 2}

CREATIVE_TAB = {
    "title": f"itemGroup.{MOD}.tab",
    "icon": f"{MOD}:{POT}",
    "items": [f"{MOD}:{POT}", f"{MOD}:{HOPPER}"],
}

LANG = {
    f"block.{MOD}.{POT}": "Botany Pot",
    f"block.{MOD}.{HOPPER}": "Hopper Botany Pot",
    f"container.{MOD}.botany_pot": "Botany Pot",
    f"itemGroup.{MOD}.tab": "Botany Pots",
}

POT_TAG = {"values": [f"{MOD}:{POT}", f"{MOD}:{HOPPER}"]}

# The jar's loot table is in the 1.20 shape (`pool.conditions` array); the
# 26.3 parser reads a pool-level `condition` object (functionalstorage,
# 2026-11-06: the 1.20 shape's pool is skipped).
def loot_table(block: str) -> dict:
    return {
        "type": "minecraft:block",
        "pools": [
            {
                "rolls": 1.0,
                "entries": [{"name": f"{MOD}:{block}", "type": "minecraft:item"}],
                "condition": {"type": "minecraft:survives_explosion"},
            }
        ],
    }


# `bookshelf:load_conditions` gates the jar's recipes on a config option this
# port has no config for; the 26.3 recipe spells ingredient keys and the
# result the newer way.
RECIPE = {
    "type": "minecraft:crafting_shaped",
    "category": "misc",
    "group": f"{MOD}:basic_pot",
    "pattern": ["M M", "MPM", " M "],
    "key": {"M": "minecraft:terracotta", "P": "minecraft:flower_pot"},
    "result": {"id": f"{MOD}:{POT}", "count": 1},
}

# The jar's hopper recipe is shapeless (hopper + botany pot), gated on
# `can_craft_hopper_pots`; the 26.3 shape takes ingredient ids directly.
HOPPER_RECIPE = {
    "type": "minecraft:crafting_shapeless",
    "category": "misc",
    "group": f"{MOD}:hopper_pot",
    "ingredients": ["minecraft:hopper", f"{MOD}:{POT}"],
    "result": {"id": f"{MOD}:{HOPPER}", "count": 1},
}


def pretty(value) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=False) + "\n").encode()


def item_def(block: str) -> dict:
    return {"model": {"type": "minecraft:model", "model": f"{MOD}:item/{block}"}}


def carried_files(jar: zipfile.ZipFile) -> dict[str, bytes]:
    """Every file the carry writes: path -> bytes."""
    names = set(jar.namelist())
    out: dict[str, bytes] = {}
    for path in VERBATIM_FILES:
        out[path] = jar.read(path)
    for directory in VERBATIM_DIRS:
        prefix = directory + "/"
        found = sorted(name for name in names if name.startswith(prefix) and name.endswith(".json"))
        if not found:
            raise SystemExit(f"the jar has no files under {directory}")
        for name in found:
            out[name] = jar.read(name)
    for block in (POT, HOPPER):
        out[f"data/{MOD}/horizon/block/{block}.json"] = pretty(BLOCK_DECL)
        out[f"assets/{MOD}/items/{block}.json"] = pretty(item_def(block))
        out[f"data/{MOD}/loot_table/blocks/{block}.json"] = pretty(loot_table(block))
    out[f"data/{MOD}/horizon/menu/basic_pot_menu.json"] = pretty(MENU_DECL)
    out[f"data/{MOD}/horizon/menu/hopper_pot_menu.json"] = pretty(HOPPER_MENU_DECL)
    out[f"data/{MOD}/horizon/creative_tab/botany_pots.json"] = pretty(CREATIVE_TAB)
    out[f"assets/{MOD}/lang/en_us.json"] = pretty(LANG)
    out[f"data/{MOD}/tags/block/botany_pots.json"] = pretty(POT_TAG)
    out[f"data/{MOD}/tags/item/botany_pots.json"] = pretty(POT_TAG)
    out[f"data/{MOD}/recipe/{MOD}/crafting/{POT}.json"] = pretty(RECIPE)
    out[f"data/{MOD}/recipe/{MOD}/crafting/{HOPPER}.json"] = pretty(HOPPER_RECIPE)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", type=Path, default=DEFAULT_JAR)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    jar_path = args.jar.resolve()
    if not jar_path.exists():
        raise SystemExit(f"missing jar: {jar_path}")
    digest = hashlib.sha1(jar_path.read_bytes()).hexdigest()
    if digest != JAR_SHA1:
        raise SystemExit(f"jar SHA-1 is {digest}, expected {JAR_SHA1}")
    with zipfile.ZipFile(jar_path) as jar:
        files = carried_files(jar)
    pending = 0
    for name, data in sorted(files.items()):
        target = ROOT / name
        current = target.read_bytes() if target.exists() else None
        if current == data:
            continue
        if args.check:
            print(f"stale: {name}", file=sys.stderr)
            pending += 1
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    if args.check:
        if pending:
            return 1
        print(f"carry check: {len(files)} files, 0 pending, jar SHA-1 {JAR_SHA1}")
        return 0
    print(f"carry: wrote {len(files)} files from jar SHA-1 {JAR_SHA1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
