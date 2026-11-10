#!/usr/bin/env python3
"""Carry the botany-pot slice of Botany Pots 21.1.44 into content/.

The jar is the ATM10 one, resolved by SHA-1 from the pack's Crash Assistant
export (see ../../_shared/carry-work/botanypots/SOURCE.md). Asset bytes are
copied verbatim; the few data files 26.3 spells differently, or that name the
one block this slice registers, are written from the jar's own values.

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

# Bytes copied unchanged from the jar, by directory.
VERBATIM_DIRS = [
    "data/botanypots/tags/item/soil",
    "data/botanypots/recipe/minecraft/crop",
    "data/botanypots/recipe/minecraft/soil",
    "data/botanypots/recipe/minecraft/interaction",
    "data/botanypots/recipe/minecraft/fertilizer",
]
VERBATIM_FILES = [
    f"assets/{MOD}/blockstates/{POT}.json",
    f"assets/{MOD}/models/block/{POT}.json",
    f"assets/{MOD}/models/block/template/pot.json",
    f"assets/{MOD}/models/item/{POT}.json",
    f"assets/{MOD}/textures/block/terracotta_pot_top.png",
    f"data/{MOD}/tags/item/harvest_items.json",
    f"data/{MOD}/tags/item/crop_generator_ignores.json",
]

MANIFEST = f"""\
# Port-owned content mod for the Botany Pots 21.1.44 slice: the botany pot
# block, its menu, and the carried soil/crop data. The models, textures and
# the blockstate are the upstream mod's own LGPL-2.1 assets, read from the
# exact ATM10 jar (see ../../_shared/carry-work/botanypots/SOURCE.md).
id = "{MOD}"
name = "Botany Pots"
version = "0.1.0"
api = "0.2"
side = "both"
capabilities = ["registries"]
"""

BLOCK_DECL = {
    "template": "minecraft:barrel",
    "properties": {
        "hardness": 1.25,
        "explosion_resistance": 4.2,
        "requires_tool": False,
        "sounds": "minecraft:terracotta",
        "occludes": False,
    },
    # Block.box(2, 0, 2, 14, 8, 14): the pot is 12 wide and 8 tall.
    "shapes": {"default": [[0.125, 0.0, 0.125, 0.875, 0.5, 0.875]]},
    "collision_shapes": {"default": [[0.125, 0.0, 0.125, 0.875, 0.5, 0.875]]},
}

MENU_DECL = {"slots": 2, "data_slots": 2}

CREATIVE_TAB = {
    "title": f"itemGroup.{MOD}.tab",
    "icon": f"{MOD}:{POT}",
    "items": [f"{MOD}:{POT}"],
}

ITEM_DEF = {
    "model": {"type": "minecraft:model", "model": f"{MOD}:item/{POT}"},
}

LANG = {
    f"block.{MOD}.{POT}": "Botany Pot",
    f"container.{MOD}.botany_pot": "Botany Pot",
    f"itemGroup.{MOD}.tab": "Botany Pots",
}

POT_TAG = {"values": [f"{MOD}:{POT}"]}

# The jar's loot table is in the 1.20 shape (`pool.conditions` array); the
# 26.3 parser reads a pool-level `condition` object (functionalstorage,
# 2026-11-06: the 1.20 shape's pool is skipped).
LOOT_TABLE = {
    "type": "minecraft:block",
    "pools": [
        {
            "rolls": 1.0,
            "entries": [{"name": f"{MOD}:{POT}", "type": "minecraft:item"}],
            "condition": {"type": "minecraft:survives_explosion"},
        }
    ],
}

# `bookshelf:load_conditions` gates the jar's recipe on a config option this
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


def pretty(value) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=False) + "\n").encode()


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
    out[f"data/{MOD}/horizon/block/{POT}.json"] = pretty(BLOCK_DECL)
    out[f"data/{MOD}/horizon/menu/basic_pot_menu.json"] = pretty(MENU_DECL)
    out[f"data/{MOD}/horizon/creative_tab/botany_pots.json"] = pretty(CREATIVE_TAB)
    out[f"assets/{MOD}/items/{POT}.json"] = pretty(ITEM_DEF)
    out[f"assets/{MOD}/lang/en_us.json"] = pretty(LANG)
    out[f"data/{MOD}/tags/block/botany_pots.json"] = pretty(POT_TAG)
    out[f"data/{MOD}/tags/item/botany_pots.json"] = pretty(POT_TAG)
    out[f"data/{MOD}/loot_table/blocks/{POT}.json"] = pretty(LOOT_TABLE)
    out[f"data/{MOD}/recipe/{MOD}/crafting/{POT}.json"] = pretty(RECIPE)
    out["horizon-mod.toml"] = MANIFEST.encode()
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
    content = ROOT / "content"
    with zipfile.ZipFile(jar_path) as jar:
        files = carried_files(jar)
    pending = 0
    for name, data in sorted(files.items()):
        target = content / name
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
