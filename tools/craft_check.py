#!/usr/bin/env python3
"""Craft the Botany Pots hopper-pot recipe in a real crafting table.

Called by tools/e2e.sh with the open game's control socket. Uses the harness's
crafting grid (`ctl screen`: slots 100-108 row-major, result 200), gives the
ingredients, and asserts:

1. one `minecraft:hopper` + one `botanypots:terracotta_botany_pot` -> one
   `botanypots:terracotta_hopper_botany_pot` (the jar's shapeless recipe), the
   crafted stack reaches the inventory, and both ingredients were consumed;
2. control: the pot alone crafts nothing (the recipe needs both);
3. control: the hopper alone crafts nothing.

The table is replaced before every case, so a failed/untaken result cannot leak
into the next grid. Exits 1 with the observed result on the first mismatch.
"""
import json
import subprocess
import sys

HOPPER = "minecraft:hopper"
POT = "botanypots:terracotta_botany_pot"
HOPPER_POT = "botanypots:terracotta_hopper_botany_pot"


def main():
    sock, ctl, x, y, z = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

    def run(*args):
        out = subprocess.run([ctl, "--socket", sock, *args], text=True, capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(args)}: {out.stdout}{out.stderr}")

    def wait(ticks=4):
        run("wait", str(ticks))

    def slots():
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"no menu is open: {screen}")
        return screen["slots"]

    def find(item):
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"missing ingredient {item} in the inventory")

    def result():
        """The result slot's stack, or None: an empty slot has `item: null`."""
        stack = [s for s in slots() if s["slot"] == 200]
        if not stack or not stack[0].get("item"):
            return None
        return stack[0]

    def place(item, targets):
        slot = find(item)
        run("click-slot", str(slot))
        wait(1)
        for target in targets:
            run("click-slot", str(target), "right")
            wait(1)
        run("click-slot", str(slot))
        wait(2)

    def setup(items):
        try:
            run("close")
        except SystemExit:
            pass
        wait(5)
        # Replace the table so its block entity, and therefore the crafting
        # grid, is fresh for this case.
        run("setblock", x, y, z, "minecraft:air")
        run("setblock", x, y, z, "minecraft:crafting_table")
        wait(2)
        # The caller's teleport can be swallowed while the inventory screen is
        # still closing (the control `tp` is client-side); a server `/tp` moves
        # the player even then. Y stays an integer.
        print("debug tp:", run("command", f"tp @s {float(x) - 0.5} {y} {float(z) + 0.5}"))
        wait(3)
        run("command", "clear @s")
        for item, count in items:
            run("give", item, str(count))
        wait(3)
        wait()
        print("debug interact:", run("interact", x, y, z))
        wait(5)

    failures = []

    # 1. The basic pot's own shaped recipe: 4 terracotta + 1 flower pot in the
    #    jar's pattern (`"M M" / "MPM" / " M "`), so every carried recipe is
    #    crafted, not just the hopper pot's.
    # The pattern has five M cells ("M M" / "MPM" / " M "), not four.
    setup([("minecraft:terracotta", 5), ("minecraft:flower_pot", 1)])
    place("minecraft:terracotta", ["100", "102", "103", "105", "107"])
    place("minecraft:flower_pot", ["104"])
    got = result()
    print("terracotta + flower pot ->", json.dumps(got))
    if not got or got.get("item") != POT or got.get("count") != 1:
        failures.append(f"the basic pot's recipe crafted {got}, expected 1 {POT}")
    else:
        run("click-slot", "200")
        wait(5)
        run("click-slot", "9")
        wait(3)
        counts = run("inventory")["counts"]
        made = counts.get(POT, 0)
        left = counts.get("minecraft:terracotta", 0) + counts.get("minecraft:flower_pot", 0)
        print(f"inventory: {made} botany pot, {left} ingredients left")
        if made < 1:
            failures.append(f"the crafted botany pot reached the inventory as {made}, not 1")
        if left:
            failures.append(f"the pot recipe did not consume its ingredients ({left} left)")

    # 2. The hopper pot's recipe: hopper + botany pot -> one hopper pot.
    setup([(HOPPER, 1), (POT, 1)])
    place(HOPPER, ["100"])
    place(POT, ["101"])
    got = result()
    print("hopper + botany pot ->", json.dumps(got))
    if not got or got.get("item") != HOPPER_POT or got.get("count") != 1:
        failures.append(f"hopper + botany pot crafted {got}, expected 1 {HOPPER_POT}")
    else:
        run("click-slot", "200")
        wait(5)
        run("click-slot", "9")
        wait(3)
        counts = run("inventory")["counts"]
        made = counts.get(HOPPER_POT, 0)
        left_pot = counts.get(POT, 0)
        left_hopper = counts.get(HOPPER, 0)
        print(
            f"inventory: {made} hopper pot, {left_pot} pot, {left_hopper} hopper"
        )
        if made < 1:
            failures.append(f"the crafted hopper pot reached the inventory as {made}, not 1")
        if left_pot or left_hopper:
            failures.append(
                f"the recipe did not consume its ingredients ({left_pot} pot, {left_hopper} hopper left)"
            )

    # 3. Control: the pot alone is not the hopper pot's recipe.
    setup([(POT, 1)])
    place(POT, ["100"])
    got = result()
    print("botany pot alone ->", json.dumps(got))
    if got is not None:
        failures.append(f"the pot alone crafted {got['item']} x{got['count']}")

    # 4. Control: the hopper alone is not the hopper pot's recipe.
    setup([(HOPPER, 1)])
    place(HOPPER, ["100"])
    got = result()
    print("hopper alone ->", json.dumps(got))
    if got is not None:
        failures.append(f"the hopper alone crafted {got['item']} x{got['count']}")

    run("close")
    wait(3)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        raise SystemExit(1)
    print(
        "recipe PASS: terracotta + flower pot craft 1 botany pot and hopper + botany pot "
        "craft 1 hopper pot, both consuming their ingredients; pot-alone and hopper-alone "
        "controls stay empty"
    )


if __name__ == "__main__":
    main()
