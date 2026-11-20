#!/usr/bin/env bash
# In-game check for Botany Pots: the basic pot (slice 1) and the hopper pot (slice 2).
#
# One offscreen creative launch, then in the Overworld on a platform:
#   1. the pot places and its block entity reads `growth=0/0 soil=none seed=none`;
#   2. dirt and wheat seeds go into the two menu slots (open the menu, click
#      each slot), and the pot reads `growth=0/1200 soil=minecraft:dirt
#      seed=minecraft:wheat_seeds`;
#   3. the growth tick runs: the counter advances over 40 ticks;
#   4. `gamerule random_tick_speed 0` does not stop it (a block-entity tick, not
#      a random tick), so the same pot keeps growing;
#   5. controls: a pot with no soil, one with sand (not in the crop's soil tag)
#      and one with a non-crop seed (a stick) stay at growth 0;
#   6. bone meals take the pot to the bone-meal cap (required - 20), then twenty
#      more ticks make it ready;
#   7. an empty-hand click harvests: the mature wheat crop's loot is popped and
#      the growth resets;
#   8. an empty-hand click on the reset pot harvests nothing;
#   8b. `/botanypots info` is operator-only: a LAN guest at permission level 0 is
#      refused while level-0 commands (`/help`, `/list`) still answer that same
#      guest, and the world's owner still reads the pot (the review finding).
#      `op`/`deop` are NOT used: they are dedicated-server commands and an
#      integrated server refuses both (commands/profiles.rs:16-23).
#
# Slice 2 — the hopper pot (`botanypots:terracotta_hopper_botany_pot`), per the
# parity rule:
#   9. its recipe crafts in a real crafting table (hopper + botany pot -> one
#      hopper pot) and consumes both ingredients; pot-alone and hopper-alone
#      controls craft nothing (`tools/craft_check.py`);
#  10. the item is give-able, the block places and reads back, it is in
#      `#botanypots:botany_pots` (a dirt control is not), and its menu has the
#      fifteen slots;
#  11. a grown crop is harvested with **no click** and lands in the twelve
#      storage slots, and the growth resets;
#  12. control: a basic pot at ready stays ready for 40 ticks and yields nothing
#      (the same state, the same wait, no auto-harvest);
#  13. a hopper pot above a chest pushes its storage into the chest;
#  14. control: with all twelve slots full the harvest is popped at the pot, not
#      destroyed (upstream's `addItem` remainder is discarded — the defect this
#      port fixes);
#  15. an unknown `botanypots:` id is refused by `give` and by `setblock`.
#
# SELFTEST=1 runs the scenario and asserts the hopper pot's storage was EMPTY,
# which must fail (exit 1): that is the counterfactual for phase 11.
# SELFTEST=basic asserts the no-soil pot DID harvest, the slice-1 counterfactual.
#
# SDK layout (0.2.x): GAME must be a **launcher-built** horizon-client carrying
# this package (`horizon-launcher native-build <port> … --trust-native-code`),
# because the mod's code is compiled into the game. The package also carries the
# content, so no `--dev-mod` is needed; DEV_MOD=1 adds the delivered
# `botanypots.hmod` as one anyway (for a build that only carries the code).
#
# CONTROL_GAME=<an unmodded launcher build> runs one extra leg first: the pot ids
# must be unknown there and the `/botanypots` command absent, which is what makes
# the scenario's positives non-vacuous.
#
# Every mod command is typed with `ctl chat "/cmd"`: `ctl command` runs the
# console path and bypasses the mod command path.
set -euo pipefail
trap 'echo "FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/botanypots
# The control binary is shared at the campaign pin it was published for; it must
# speak the same protocol as GAME, so point CTL at a horizon-ctl built from the
# game's own build when one is published for it. The game is the launcher build
# carrying this package.
CTL=${CTL:-$CLONE/ports/_shared/bin/horizon-1d63e0a5/horizon-ctl}
GAME=${GAME:-$PORT/target/horizon-cargo/fast/horizon-client}
CONTROL_GAME=${CONTROL_GAME:-}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/botanypots-e2e.sock}
GSOCK=${GSOCK:-/tmp/opencode/botanypots-e2e-guest.sock}
SELFTEST=${SELFTEST:-0}
# DEV_MOD=1 also hands the delivered package to the game with `--dev-mod`.
DEV_MOD=${DEV_MOD:-0}
WORLD=BotanyPotsE2E
CONTROL_WORLD=BotanyPotsControl

POT=botanypots:terracotta_botany_pot
HOPPER=botanypots:terracotta_hopper_botany_pot

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/horizon-mod.toml" ] || { echo "missing package manifest: $PORT/horizon-mod.toml" >&2; exit 1; }
[ -f "$PORT/botanypots.hmod" ] || { echo "missing package: $PORT/botanypots.hmod" >&2; exit 1; }

SCRATCH=$(mktemp -d "${E2E_TMP:-/tmp/opencode}"/botanypots-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
# The LAN guest's own control client (its own socket, its own game home). A
# guest's command is a network command run by the server at the guest's own
# permission level, which is 0 when the world was opened with guest commands
# off (`lan open 0`; lan/hub.rs `default_permission`).
gctl() { "$CTL" --socket "$GSOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
say() { echo "== $* =="; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
dropped_item() {
    ctl entities "${2:-10}" item \
        | jq -r --arg i "$1" '[.entities[] | select(.kind == "item" and .item.item == $i) | .item.count] | add // 0'
}
info() {
    ctl chat "/botanypots info $1 $2 $3" >/dev/null
    ctl wait 2 >/dev/null
    local reply line
    reply=$(ctl messages 4)
    line=$(printf '%s' "$reply" | jq -r '.chat[]' 2>/dev/null | grep -m1 -E "^botanypots:[a-z0-9_]+: " || true)
    if [ -z "$line" ]; then
        # A silent readout used to fail with only `readout: ''` (2026-11-10), which
        # says nothing about *why*; keep the reply so the next run can tell an
        # unregistered command from a late chat line or a missing block entity.
        echo "  no readout for /botanypots info $1 $2 $3; last chat: $reply" >&2
    fi
    printf '%s\n' "$line"
}
growth_of() { info "$1" "$2" "$3" | sed -n 's/.*growth=\([0-9][0-9]*\)\/.*/\1/p'; }
required_of() { info "$1" "$2" "$3" | sed -n 's/.*growth=[0-9][0-9]*\/\([0-9][0-9]*\).*/\1/p'; }
soil_of() { info "$1" "$2" "$3" | sed -n 's/.*soil=\([^ ]*\).*/\1/p'; }
seed_of() { info "$1" "$2" "$3" | sed -n 's/.*seed=\([^ ]*\).*/\1/p'; }
ready_of() { info "$1" "$2" "$3" | sed -n 's/.*ready=\([a-z]*\).*/\1/p'; }
stand_near() { # x z
    ctl tp "$1.5" 101 "$(($2 + 3)).5" >/dev/null
    ctl look 180 0 >/dev/null
    ctl wait 4 >/dev/null
}
place_pot() { # x y z
    stand_near "$1" "$3"
    ctl setblock "$1" "$2" $(( $3 - 1 )) minecraft:stone >/dev/null
    ctl give "$POT" 1 >/dev/null || fail "cannot give $POT"
    ctl wait 2 >/dev/null
    ctl select "$POT" >/dev/null || fail "cannot select $POT"
    ctl wait 2 >/dev/null
    ctl place "$1" "$2" "$3" --item "$POT" >/dev/null || fail "cannot place $POT at $1 $2 $3"
    ctl wait 3 >/dev/null
    [ "$(ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"')" = "$POT" ] \
        || fail "the placed block at $1 $2 $3 is not the pot"
}
place_hopper() { # x y z  (the block below is set by the caller)
    stand_near "$1" "$3"
    ctl command "clear @s" >/dev/null
    ctl give "$HOPPER" 1 >/dev/null || fail "cannot give $HOPPER"
    ctl wait 2 >/dev/null
    ctl select "$HOPPER" >/dev/null || fail "cannot select $HOPPER"
    ctl wait 2 >/dev/null
    ctl place "$1" "$2" "$3" --item "$HOPPER" >/dev/null || fail "cannot place $HOPPER at $1 $2 $3"
    ctl wait 3 >/dev/null
    [ "$(ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"')" = "$HOPPER" ] \
        || fail "the placed block at $1 $2 $3 is not the hopper pot"
}
put_in_slot() { # pot-slot item
    # A menu click moves the cursor stack, not the hotbar stack: pick the item
    # up from its inventory slot first, then click the pot's slot.
    local src
    src=$(ctl screen | jq -r --arg i "$2" \
        '[.slots[] | select(.slot < 36 and .item == $i) | .slot] | map(.) | .[0] // ""' 2>/dev/null || true)
    if [ -z "$src" ]; then
        echo "screen with no $2:" >&2
        ctl screen >&2
        fail "$2 is not in the inventory"
    fi
    ctl click-slot "$src" >/dev/null || fail "cannot pick up $2 from slot $src"
    ctl wait 2 >/dev/null
    ctl click-slot "$1" >/dev/null || fail "cannot place $2 into pot slot $1"
    ctl wait 2 >/dev/null
}

open_menu() { # x y z [expected container slots]
    local want=${4:-2}
    ctl interact "$1" "$2" "$3" >/dev/null || fail "the click did not open the pot menu"
    ctl wait-for screen container --timeout 10 >/dev/null \
        || fail "the pot did not open a menu (screen=$(ctl state | jq -r '.screen // ""'))"
    local slots
    slots=$(ctl screen | jq '[.slots[] | select(.slot >= 300)] | length' 2>/dev/null || echo 0)
    [ "$slots" = "$want" ] || fail "the pot menu shows $slots slots, expected $want"
}

insert_slots() { # x y z soil seed [expected container slots]
    local want=${6:-2}
    ctl command "clear @s" >/dev/null
    ctl give "$4" 1 >/dev/null || fail "cannot give $4"
    ctl wait 2 >/dev/null
    open_menu "$1" "$2" "$3" "$want"
    echo "menu slots: $want"
    put_in_slot 300 "$4"
    ctl close >/dev/null 2>&1 || true
    ctl wait 3 >/dev/null
    ctl command "clear @s" >/dev/null
    ctl give "$5" 1 >/dev/null || fail "cannot give $5"
    ctl wait 2 >/dev/null
    open_menu "$1" "$2" "$3" "$want"
    put_in_slot 301 "$5"
    ctl close >/dev/null 2>&1 || true
    ctl wait 4 >/dev/null
}

# The hopper pot's storage slots are 303..314 (300 is soil, 301 seed, 302 tool).
storage_count() { # item -> the item's total in the twelve storage slots
    ctl screen \
        | jq -r --arg i "$1" \
            '[.slots[] | select(.slot >= 303 and .slot <= 314 and .item == $i) | .count] | add // 0'
}
storage_slots_used() { # item -> how many storage slots hold it
    ctl screen \
        | jq -r --arg i "$1" \
            '[.slots[] | select(.slot >= 303 and .slot <= 314 and .item == $i)] | length'
}
# An empty hand: a right click on a pot holding bone meal fertilises instead of
# opening the menu, so a storage read must clear the selected hotbar slot first.
empty_hand() {
    ctl command "item replace entity @s hotbar.0 with minecraft:air" >/dev/null 2>&1 || true
    ctl select 1 >/dev/null 2>&1 || true
    ctl wait 2 >/dev/null
}
# A pot's own storage readout, with its menu opened and closed around it.
pot_storage_count() { # x y z item
    empty_hand
    open_menu "$1" "$2" "$3" 15
    local n
    n=$(storage_count "$4")
    ctl close >/dev/null 2>&1 || true
    ctl wait 2 >/dev/null
    printf '%s' "$n"
}
# What a container below holds, read from the server's own block data: the
# harness cannot open a vanilla chest menu at this pin (the click lands and
# `screen` stays `playing`), so the export is read back as NBT, which is the
# server's authoritative contents.
chest_items() { # x y z -> the /data get reply
    ctl command "data get block $1 $2 $3 Items" >/dev/null
    ctl wait 4 >/dev/null
    ctl messages 6 | jq -r '.chat[]' | grep -m1 "block data" || true
}
# Bone meal a pot to its cap without ever clicking a ready pot: a click on a
# ready basic pot harvests, and a click on a ready hopper pot opens the menu.
bone_meal_to_ready() { # x y z [tries]
    local tries=${4:-3} i growth required
    stand_near "$1" "$3"
    ctl command "clear @s" >/dev/null
    ctl command "item replace entity @s hotbar.0 with minecraft:bone_meal 8" >/dev/null \
        || ctl give minecraft:bone_meal 8 >/dev/null || fail "cannot give bone meal"
    ctl select 1 >/dev/null || fail "cannot select the bone-meal hotbar slot"
    ctl wait 2 >/dev/null
    [ "$(ctl state | jq -r '.held.item // ""')" = "minecraft:bone_meal" ] \
        || fail "the held item is not bone meal"
    for i in $(seq "$tries"); do
        if [ "$(ready_of "$1" "$2" "$3")" = true ]; then
            return 0
        fi
        # Only fertilise below the bone-meal cap: a pot at the cap cannot grow, and a
        # click on one that ripened inside the two-tick read window harvests it
        # instead (the trap the notes record). At the cap it ripens on its own.
        growth=$(growth_of "$1" "$2" "$3")
        required=$(required_of "$1" "$2" "$3")
        if [ -n "$growth" ] && [ -n "$required" ] && [ "$growth" -lt $((required - 20)) ]; then
            ctl interact "$1" "$2" "$3" >/dev/null || fail "the bone meal click failed"
            ctl close >/dev/null 2>&1 || true
        fi
        ctl wait 25 >/dev/null
    done
    for i in $(seq 12); do
        if [ "$(ready_of "$1" "$2" "$3")" = true ]; then
            return 0
        fi
        ctl wait 5 >/dev/null
    done
    [ "$(ready_of "$1" "$2" "$3")" = true ] || fail "the pot is not ready after $tries bone meals"
}

# The same for a hopper pot, which never *stays* ready: its tick harvests the
# moment it reaches the required ticks, so readiness is not observable. Three
# meals always reach the cap (3 x 400 > required - 20), and twenty more ticks
# make it ready, so the caller only has to wait and read the storage.
bone_meal_to_cap() { # x y z [clicks]
    local clicks=${4:-3} i
    stand_near "$1" "$3"
    ctl command "clear @s" >/dev/null
    ctl command "item replace entity @s hotbar.0 with minecraft:bone_meal 8" >/dev/null \
        || ctl give minecraft:bone_meal 8 >/dev/null || fail "cannot give bone meal"
    ctl select 1 >/dev/null || fail "cannot select the bone-meal hotbar slot"
    ctl wait 2 >/dev/null
    [ "$(ctl state | jq -r '.held.item // ""')" = "minecraft:bone_meal" ] \
        || fail "the held item is not bone meal"
    local i before after last="" required
    for i in $(seq "$clicks"); do
        before=$(growth_of "$1" "$2" "$3")
        required=$(required_of "$1" "$2" "$3")
        # The hopper pot harvests the tick it ripens, so a growth that fell since the
        # last read *is* the harvest — there is nothing left to fertilise. (The pot
        # can ripen during the wait after a meal, before the next click: a run on
        # 2026-11-20 measured `growth 3 -> 566` and the old `&&` chain then exited
        # the script under `set -e` instead of stopping the loop.)
        if [ -n "$last" ] && [ -n "$before" ] && [ "$before" -lt "$last" ]; then
            echo "  bone meal $i: harvested before the click (growth $last -> $before)"
            return 0
        fi
        # A pot at the bone-meal cap cannot grow; clicking it only risks a harvest if
        # it ripened inside the read window, so wait for its own tick instead.
        if [ -n "$before" ] && [ -n "$required" ] && [ "$before" -ge $((required - 20)) ]; then
            ctl wait 25 >/dev/null
            continue
        fi
        # Aim at the south face: the pot's shape is only half a block high, and a
        # click aimed at the block's centre sits on that shape's top edge (a click
        # there sometimes misses entirely).
        ctl interact "$1" "$2" "$3" south >/dev/null || fail "the bone meal click failed"
        # A click on a pot already at the cap falls through to the menu.
        ctl close >/dev/null 2>&1 || true
        ctl wait 25 >/dev/null
        after=$(growth_of "$1" "$2" "$3")
        echo "  bone meal $i: growth $before -> $after"
        # A harvest resets the growth to below where it was: the pot is done.
        if [ -n "$after" ] && [ -n "$before" ] && [ "$after" -lt "$before" ]; then
            return 0
        fi
        last=$after
    done
}

# Fill a hopper pot's twelve storage slots with a full stack of sticks each, so
# the next harvest cannot fit (the overflow control). Left-click swaps the held
# stack into an empty slot, so each slot takes one pick-up and one click.
fill_storage_with_sticks() { # x y z
    ctl command "clear @s" >/dev/null
    local i slot src
    for i in $(seq 12); do
        ctl command "give @s minecraft:stick 64" >/dev/null
    done
    ctl wait 5 >/dev/null
    open_menu "$1" "$2" "$3" 15
    for slot in $(seq 303 314); do
        src=$(ctl screen | jq -r \
            '[.slots[] | select(.slot < 36 and .item == "minecraft:stick") | .slot] | .[0] // ""')
        [ -n "$src" ] || fail "no stick stack left for storage slot $slot"
        ctl click-slot "$src" >/dev/null || fail "cannot pick up the sticks"
        ctl wait 1 >/dev/null
        ctl click-slot "$slot" >/dev/null || fail "cannot fill storage slot $slot"
        ctl wait 1 >/dev/null
    done
    ctl close >/dev/null 2>&1 || true
    ctl wait 3 >/dev/null
}

cleanup() {
    local status=$?
    gctl quit >/dev/null 2>&1 || true
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
    # Last line of every run: `check-e2e-logs.py` reads it as the verdict.
    echo "EXIT:$status"
}
trap cleanup EXIT

launch() { # launch [WORLD] [DIRECTORY] [GAME]
    local world=${1:-$WORLD} dir=${2:-$SCRATCH} game=${3:-$GAME}
    rm -f "$SOCK"
    cd "$dir"
    local args=(--game "$game" --world "$world" --seed 20261105 --creative --offscreen --wait
                --game-dir "$dir/game" --resources "$RES")
    if [ "$DEV_MOD" = 1 ]; then
        say "launch (offscreen renderer, creative, --dev-mod botanypots.hmod)"
        args+=(--dev-mod "$PORT/botanypots.hmod")
    else
        say "launch (offscreen renderer, creative, the launcher build carries the package)"
    fi
    "$CTL" --socket "$SOCK" launch "${args[@]}"
    ctl wait-ready 180
    if grep -q "content mods not loaded" "${SOCK}.log" 2>/dev/null; then
        grep "content mods not loaded" "${SOCK}.log" >&2
        fail "the content mod did not load"
    fi
}

# CONTROL_GAME: an unmodded launcher build in its own scratch home and folder. The
# pot ids must be unknown there and no `/botanypots` command may answer; if either
# resolves, the main run proves nothing about this package.
control_game_leg() {
    say "control: an unmodded launcher build (no package)"
    local dir=$SCRATCH/control
    mkdir -p "$dir/game"
    (
        export HORIZON_HOME=$dir/game HORIZON_LAUNCHER_HOME=$dir/launcher \
               XDG_DATA_HOME=$dir/data XDG_CONFIG_HOME=$dir/config
        DEV_MOD=0 launch "$CONTROL_WORLD" "$dir" "$CONTROL_GAME"
        local x z
        x=$(ctl state | jq -r '.player.position[0]' | cut -d. -f1)
        z=$(ctl state | jq -r '.player.position[2]' | cut -d. -f1)
        ctl command "fill $((x-4)) 100 $((z-4)) $((x+4)) 100 $((z+4)) minecraft:stone" >/dev/null
        ctl command "fill $((x-4)) 101 $((z-4)) $((x+4)) 110 $((z+4)) minecraft:air" >/dev/null
        ctl tp "$x.5" 101 "$((z+3)).5" >/dev/null
        ctl wait 10
        ctl command "give @s botanypots:terracotta_botany_pot 1" >/dev/null || true
        ctl setblock "$((x-2))" 102 "$((z+1))" botanypots:terracotta_botany_pot >/dev/null || true
        ctl setblock "$((x-4))" 102 "$((z+1))" botanypots:terracotta_hopper_botany_pot >/dev/null || true
        ctl wait 6
        local name held hopper reply
        name=$(ctl block "$((x-2))" 102 "$((z+1))" | jq -r '.block // ""')
        hopper=$(ctl block "$((x-4))" 102 "$((z+1))" | jq -r '.block // ""')
        held=$(count_item botanypots:terracotta_botany_pot)
        echo "  placed blocks: $name and $hopper; pots in inventory: $held"
        [ "$name" = "minecraft:air" ] || fail "the control game holds $name, so the pot id was known"
        [ "$hopper" = "minecraft:air" ] || fail "the control game holds $hopper, so the hopper pot id was known"
        [ "$held" = 0 ] || fail "the control game holds $held pot items, so the pot id was known"
        ctl chat "/botanypots info $((x-2)) 102 $((z+1))" >/dev/null
        ctl wait 4
        # The typed line echoes back in chat; only the mod's own reply matches
        # `<block>: …` or `not a botany pot`, so match those shapes only.
        reply=$(ctl messages 6 | jq -r '.chat[]' \
            | grep -E "^botanypots:[a-z0-9_]+: |not a botany pot" || true)
        echo "  native command reply: ${reply:-none}"
        [ -z "$reply" ] || fail "the control game answered a /botanypots command: $reply"
        echo "  without the package: no pot block, no hopper pot block, no pot item, no pot command"
        ctl quit >/dev/null 2>&1 || true
    )
    sleep 3
    rm -rf "$dir"
}

if [ -n "$CONTROL_GAME" ]; then control_game_leg; fi
launch

say "an Overworld platform at y=100, away from the terrain"
PX=$(ctl state | jq -r '.player.position[0]' | cut -d. -f1)
PZ=$(ctl state | jq -r '.player.position[2]' | cut -d. -f1)
ctl command "fill $((PX-8)) 100 $((PZ-8)) $((PX+8)) 100 $((PZ+8)) minecraft:stone" >/dev/null
ctl command "fill $((PX-8)) 101 $((PZ-8)) $((PX+8)) 110 $((PZ+8)) minecraft:air" >/dev/null
ctl tp "$PX.5" 101 "$(($PZ+3)).5" >/dev/null
ctl wait 10
ctl command "gamerule spawn_mobs false" >/dev/null
ctl command "gamerule spawn_monsters false" >/dev/null
ctl command "kill @e[type=!minecraft:player]" >/dev/null
ctl wait 10
Y=102
X1=$PX; Z1=$((PZ + 1))
X2=$((PX - 2)); Z2=$((PZ + 1))
X3=$((PX - 4)); Z3=$((PZ + 1))
X4=$((PX - 6)); Z4=$((PZ + 1))
X5=$((PX + 2)); Z5=$((PZ + 1))
X6=$((PX + 4)); Z6=$((PZ + 1))
X7=$((PX - 8)); Z7=$((PZ + 4))
X8=$((PX + 6)); Z8=$((PZ + 4))
ctl look 180 0
ctl wait 4

say "the pot places and starts empty"
place_pot "$X1" "$Y" "$Z1"
line=$(info "$X1" "$Y" "$Z1")
echo "readout: $line"
echo "$line" | grep -q "soil=none seed=none" || fail "the empty pot reads '$line'"
[ "$(growth_of "$X1" "$Y" "$Z1")" = 0 ] || fail "an empty pot has growth"

say "soil and seed go into the menu's two slots"
insert_slots "$X1" "$Y" "$Z1" minecraft:dirt minecraft:wheat_seeds
line=$(info "$X1" "$Y" "$Z1")
echo "readout: $line"
echo "$line" | grep -q "soil=minecraft:dirt seed=minecraft:wheat_seeds" || fail "the slots did not take: $line"
[ "$(required_of "$X1" "$Y" "$Z1")" = 1200 ] || fail "wheat in dirt needs 1200 ticks, read $(required_of "$X1" "$Y" "$Z1")"
# Every `/botanypots info` read costs two ticks, so "just planted" and "just
# harvested" are read a few ticks late: assert the counter restarted, not 0.
[ "$(growth_of "$X1" "$Y" "$Z1")" -lt 100 ] || fail "a freshly planted pot already grew"

say "the growth tick advances in dirt"
# Measure the window itself: every `/botanypots info` read waits two ticks, so an
# absolute "growth after 40 ticks" bound counted the reads too (a 66-in-40 read
# on 2026-11-20, the same boundary flake the 0.1.0 notes recorded at 61).
before=$(growth_of "$X1" "$Y" "$Z1")
ctl wait 40
after=$(growth_of "$X1" "$Y" "$Z1")
delta=$((after - before))
echo "growth over 40 ticks: $before -> $after (+$delta)"
[ "$delta" -ge 30 ] || fail "the pot grew $delta ticks in 40, expected at least 30"
[ "$delta" -le 50 ] || fail "the pot grew $delta ticks in 40, expected at most 50"

say "random_tick_speed 0 does not stop a block-entity tick"
ctl command "gamerule random_tick_speed 0" >/dev/null
before=$after
ctl wait 40
after=$(growth_of "$X1" "$Y" "$Z1")
echo "growth with random_tick_speed 0: $before -> $after"
[ "$after" -gt "$before" ] || fail "random_tick_speed 0 stopped the growth: $before -> $after"

say "control: a pot with no soil does not grow"
place_pot "$X2" "$Y" "$Z2"
# A crop seed in the seed slot, and the soil slot left empty.
ctl command "clear @s" >/dev/null
ctl give minecraft:wheat_seeds 1 >/dev/null || fail "cannot give wheat seeds to the no-soil pot"
ctl wait 2 >/dev/null
open_menu "$X2" "$Y" "$Z2"
put_in_slot 301 minecraft:wheat_seeds
ctl close >/dev/null 2>&1 || true
ctl wait 30
line=$(info "$X2" "$Y" "$Z2")
echo "no-soil readout: $line"
[ "$(soil_of "$X2" "$Y" "$Z2")" = "none" ] || fail "the no-soil pot has soil"
[ "$(growth_of "$X2" "$Y" "$Z2")" = 0 ] || fail "a pot with no soil grew"

say "control: sand is not in the wheat crop's soil tag"
place_pot "$X3" "$Y" "$Z3"
insert_slots "$X3" "$Y" "$Z3" minecraft:sand minecraft:wheat_seeds
before=$(growth_of "$X3" "$Y" "$Z3")
ctl wait 30
after=$(growth_of "$X3" "$Y" "$Z3")
echo "sand soil growth: $before -> $after"
[ "$after" = 0 ] || fail "wheat grew on sand ($before -> $after); the soil tag gate is broken"

say "control: a stick is not a crop seed"
place_pot "$X4" "$Y" "$Z4"
insert_slots "$X4" "$Y" "$Z4" minecraft:dirt minecraft:stick
before=$(growth_of "$X4" "$Y" "$Z4")
ctl wait 30
after=$(growth_of "$X4" "$Y" "$Z4")
echo "stick seed growth: $before -> $after"
[ "$after" = 0 ] || fail "a stick grew ($before -> $after); the crop gate is broken"

say "bone meal forces growth to the cap"
stand_near "$X1" "$Z1"
ctl command "clear @s" >/dev/null
# The hotbar slot is named, then selected: `give` alone may fill a main
# inventory slot, which `select ITEM` cannot select.
ctl command "item replace entity @s hotbar.0 with minecraft:bone_meal 8" >/dev/null \
    || ctl give minecraft:bone_meal 8 >/dev/null || fail "cannot give bone meal"
ctl select 1 >/dev/null || fail "cannot select the bone-meal hotbar slot"
ctl wait 2 >/dev/null
held=$(ctl state | jq -r '.held.item // ""')
[ "$held" = "minecraft:bone_meal" ] || fail "the held item is '$held', expected bone meal"
before=$(growth_of "$X1" "$Y" "$Z1")
ctl interact "$X1" "$Y" "$Z1" >/dev/null || fail "bone meal click failed"
ctl wait 25
first=$(growth_of "$X1" "$Y" "$Z1")
echo "after bone meal 1: $(info "$X1" "$Y" "$Z1")"
[ "$first" -ge $((before + 400)) ] || fail "bone meal added $(($first - before)) growth, expected at least 400"
# A second meal reaches the required - 20 cap; a right click on a pot that ripened
# inside the two-tick read window harvests instead of fertilising, so only fertilise
# below the cap and let the pot ripen on its own ticks.
second_growth=$(growth_of "$X1" "$Y" "$Z1")
second_required=$(required_of "$X1" "$Y" "$Z1")
if [ -n "$second_growth" ] && [ -n "$second_required" ] \
    && [ "$second_growth" -lt $((second_required - 20)) ]; then
    ctl interact "$X1" "$Y" "$Z1" >/dev/null || fail "bone meal click failed"
    ctl wait 25
    echo "after bone meal 2: $(info "$X1" "$Y" "$Z1")"
fi
for _ in $(seq 12); do
    if [ "$(ready_of "$X1" "$Y" "$Z1")" = true ]; then
        break
    fi
    ctl wait 5 >/dev/null
done
line=$(info "$X1" "$Y" "$Z1")
echo "fertilised: $line"
[ "$(ready_of "$X1" "$Y" "$Z1")" = true ] || fail "the pot is not ready after bone meal: $line"

say "harvest pops the mature wheat loot and resets growth"
ctl command "clear @s" >/dev/null
ctl wait 2 >/dev/null
# Stand beside the pot so a landing drop is in pickup range, and read the
# ground too: the assertion is the loot the mature crop's table rolls.
ctl tp "$X1.5" 101 "$(($Z1 + 1)).5" >/dev/null
ctl wait 4 >/dev/null
ctl interact "$X1" "$Y" "$Z1" >/dev/null || fail "the harvest click failed"
ctl wait 20
wheat=$(count_item minecraft:wheat)
dropped=$(dropped_item minecraft:wheat)
seeds=$(count_item minecraft:wheat_seeds)
echo "harvest: wheat in inventory $wheat, wheat on the ground $dropped, seeds $seeds"
[ $((wheat + dropped)) -ge 1 ] || fail "the harvest gave 0 wheat, expected at least 1"
line=$(info "$X1" "$Y" "$Z1")
echo "after harvest: $line"
[ "$(growth_of "$X1" "$Y" "$Z1")" -lt 200 ] || fail "the harvest did not reset growth: $line"
[ "$(seed_of "$X1" "$Y" "$Z1")" = "minecraft:wheat_seeds" ] || fail "the harvest lost the seed: $line"

say "an empty click on the reset pot harvests nothing"
before=$(( $(count_item minecraft:wheat) + $(dropped_item minecraft:wheat) ))
ctl interact "$X1" "$Y" "$Z1" >/dev/null || fail "the reset-pot click failed"
ctl wait 8
after=$(( $(count_item minecraft:wheat) + $(dropped_item minecraft:wheat) ))
echo "second click wheat: $before -> $after"
[ "$after" -le "$before" ] || fail "a young pot harvested wheat: $before -> $after"

say "the readout needs an operator"
# `/botanypots info` names a pot's soil, seed and growth at coordinates the caller
# chooses, so a non-operator must not read it (the review finding). The launched
# player is the world's owner, so it reads the pot; the real non-operator is a LAN
# guest at permission level 0.
#
# `op`/`deop` cannot produce that guest: both are dedicated-server commands, and
# an integrated server refuses them with `command.unknown.command`
# (`commands/profiles.rs:16-23`, `dedicated_lists`). The first version of this
# phase ran `deop`, grepped the window for `Unknown or incomplete command`, and
# matched the *failed `deop`'s own* refusal while the player stayed level 4 — a
# passing assertion that proved nothing. The refusal text alone is ambiguous for
# the same reason, so this phase is a differential: the same guest runs level-0
# commands that must answer, and only then the level-2 usage that must not.
line=$(info "$X1" "$Y" "$Z1")
echo "  as an operator: $line"
echo "$line" | grep -q "^botanypots:terracotta_botany_pot: growth=" \
    || fail "an operator could not read the pot: $line"
# A position holding no pot names no block: the readout must not double as a
# world probe (the air above the pot is the nearest non-pot position).
ctl chat "/botanypots info $X1 $((Y + 1)) $Z1" >/dev/null
ctl wait 4 >/dev/null
NOT_POT=$(ctl messages 8 | jq -r '.chat[]' | grep -m1 -E '^(not a botany pot|[a-z0-9_]+:[a-z0-9_/]+: not a botany pot)$' || true)
echo "  non-pot readout: ${NOT_POT:-none}"
[ "$NOT_POT" = "not a botany pot" ] \
    || fail "a non-pot position answered '$NOT_POT'; it must name no block"

# The guest. `lan open 0` opens the world with guest commands OFF, and an
# integrated server then gives every guest level 0 (`lan/hub.rs`
# `default_permission`: 2 only when guest commands are allowed).
LAN_PORT=$(ctl lan open 0 | jq -r '.port')
[ "$LAN_PORT" != "null" ] || fail "the host did not open its world to LAN"
echo "  LAN port $LAN_PORT (guest commands off: a guest joins at level 0)"
rm -f "$GSOCK"
HORIZON_HOME=$SCRATCH/guest "$CTL" --socket "$GSOCK" launch \
    --game "$GAME" --headless --resources "$RES" --no-pause >/dev/null
sleep 3
CONNECT=$(gctl connect "127.0.0.1:$LAN_PORT" Guest 2>&1 || true)
echo "  guest connect: $CONNECT"
JOINED=false
for _ in $(seq 1 60); do
    if [ "$(gctl status 2>/dev/null | jq -r '.server.joined // false')" = true ] \
        && [ "$(gctl status 2>/dev/null | jq -r '.server.loaded // false')" = true ]; then
        JOINED=true
        break
    fi
    sleep 2
done
[ "$JOINED" = true ] || fail "the guest never joined the LAN world"
# Half one of the differential: the guest's command path is alive at level 0.
# `/help` prints the usages a level-0 player may run, and `/list` is a server
# reply (the guest's own name in it). Without these lines a refusal of
# `/botanypots info` could mean "guests cannot run commands at all".
gctl command "/help" >/dev/null
HELP_REPLY=""
for _ in $(seq 1 20); do
    HELP_REPLY=$(gctl messages 12 | jq -r '.chat[]' 2>/dev/null | grep -m1 '^/' || true)
    [ -n "$HELP_REPLY" ] && break
    sleep 1
done
echo "  the level-0 guest runs /help: ${HELP_REPLY:-<none>}"
[ -n "$HELP_REPLY" ] \
    || fail "the level-0 guest cannot run /help, so a refusal below would prove nothing"
gctl command "/list" >/dev/null
LIST_REPLY=""
for _ in $(seq 1 20); do
    LIST_REPLY=$(gctl messages 6 | jq -r '.chat[]' 2>/dev/null | grep -m1 'players online' || true)
    [ -n "$LIST_REPLY" ] && break
    sleep 1
done
echo "  the level-0 guest runs /list: ${LIST_REPLY:-<none>}"
[ -n "$LIST_REPLY" ] || fail "the level-0 guest cannot run /list either"
# Half two: the same guest asks for the level-2 usage and is refused, with no
# readout in its window. If the command were still level 0 this assertion fails;
# if guest commands were off, the two lines above fail first.
gctl command "/botanypots info $X1 $Y $Z1" >/dev/null
GUEST_WINDOW=""
for _ in $(seq 1 20); do
    GUEST_WINDOW=$(gctl messages 4 | jq -r '.chat[]' 2>/dev/null || true)
    grep -qiE 'unknown or incomplete command|permission|incorrect argument' <<<"$GUEST_WINDOW" && break
    sleep 1
done
echo "  as a level-0 guest: $(tr '\n' ' ' <<<"$GUEST_WINDOW")"
grep -qiE 'unknown or incomplete command|permission|incorrect argument' <<<"$GUEST_WINDOW" \
    || fail "a level-0 guest was not refused: $GUEST_WINDOW"
if grep -qE 'growth=|terracotta_botany_pot:' <<<"$GUEST_WINDOW"; then
    fail "a level-0 guest received the readout: $GUEST_WINDOW"
fi
gctl quit >/dev/null 2>&1 || true
sleep 1
# Close the LAN publication again: the rest of the run is the owner's alone.
ctl lan close >/dev/null 2>&1 || true
# The owner still reads the pot: the refusal was the guest's level, not the world.
line=$(info "$X1" "$Y" "$Z1")
echo "  as an operator after the guest left: $line"
echo "$line" | grep -q "^botanypots:terracotta_botany_pot: growth=" \
    || fail "the operator lost the readout after the guest leg: $line"

# ---------------------------------------------------------------------------
# Slice 2 — the hopper pot
# ---------------------------------------------------------------------------

say "the hopper pot's recipe crafts in a real table and consumes its ingredients"
CTX=$((PX - 8)); CTZ=$((PZ - 2))
ctl command "fill $((CTX-2)) 101 $((CTZ-2)) $((CTX+2)) 101 $((CTZ+2)) minecraft:air" >/dev/null
ctl command "fill $((CTX-2)) 100 $((CTZ-2)) $((CTX+2)) 100 $((CTZ+2)) minecraft:stone" >/dev/null
ctl setblock "$CTX" "$Y" "$CTZ" minecraft:crafting_table >/dev/null || fail "cannot place the crafting table"
ctl wait 3 >/dev/null
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" "$CTX" "$Y" "$CTZ" \
    || fail "the hopper pot's recipe check failed"

say "the hopper pot is give-able and places"
ctl command "clear @s" >/dev/null
ctl give "$HOPPER" 1 >/dev/null || fail "cannot give $HOPPER"
ctl wait 3 >/dev/null
[ "$(count_item "$HOPPER")" -ge 1 ] || fail "the given hopper pot is not in the inventory"
ctl setblock "$X5" $((Y - 1)) "$Z5" minecraft:stone >/dev/null
place_hopper "$X5" "$Y" "$Z5"
echo "placed: $(ctl block "$X5" "$Y" "$Z5" | jq -r '.block')"

say "both pots are in #botanypots:botany_pots, and stone is not"
ctl command "execute in minecraft:overworld if block $X5 $Y $Z5 #botanypots:botany_pots run say TAG_HOPPER" >/dev/null
ctl command "execute in minecraft:overworld if block $X1 $Y $Z1 #botanypots:botany_pots run say TAG_BASIC" >/dev/null
ctl command "execute in minecraft:overworld if block $X8 $Y $Z8 #botanypots:botany_pots run say TAG_STONE" >/dev/null
ctl wait 6 >/dev/null
tags=$(ctl messages 8 | jq -r '.chat[]' 2>/dev/null || true)
echo "tag replies: $(printf '%s' "$tags" | tr '\n' ' ')"
printf '%s' "$tags" | grep -q "TAG_HOPPER" || fail "the hopper pot is not in #botanypots:botany_pots"
printf '%s' "$tags" | grep -q "TAG_BASIC" || fail "the basic pot is not in #botanypots:botany_pots"
if printf '%s' "$tags" | grep -q "TAG_STONE"; then
    fail "the stone control matched #botanypots:botany_pots, so the tag check is not discriminating"
fi

say "the hopper pot opens its fifteen-slot menu"
open_menu "$X5" "$Y" "$Z5" 15
ctl close >/dev/null 2>&1 || true
ctl wait 3 >/dev/null

say "a grown crop is harvested with no click into the twelve storage slots"
insert_slots "$X5" "$Y" "$Z5" minecraft:dirt minecraft:wheat_seeds 15
line=$(info "$X5" "$Y" "$Z5")
echo "readout: $line"
echo "$line" | grep -q "soil=minecraft:dirt seed=minecraft:wheat_seeds" || fail "the hopper pot's slots did not take: $line"
# Two meals reach the cap (required - 20) from any starting point below it; the
# third is a no-op at the cap. Then twenty ticks make it ready and the tick
# harvests by itself.
bone_meal_to_cap "$X5" "$Y" "$Z5"
ctl wait 40 >/dev/null
stored=$(pot_storage_count "$X5" "$Y" "$Z5" minecraft:wheat)
seeds_stored=$(pot_storage_count "$X5" "$Y" "$Z5" minecraft:wheat_seeds)
line=$(info "$X5" "$Y" "$Z5")
echo "after the self-harvest: storage wheat $stored, seeds $seeds_stored; $line"
[ "$stored" -ge 1 ] || fail "the hopper pot harvested nothing into its storage without a click: $line"
# The menu reads and the `ctl wait`s between the harvest and this read let the
# pot regrow, so the proof of a reset is that it is no longer clamped at the
# required ticks (a pot that never harvested would still read ready=true).
[ "$(ready_of "$X5" "$Y" "$Z5")" = false ] || fail "the self-harvest did not reset the growth: $line"
[ "$(seed_of "$X5" "$Y" "$Z5")" = "minecraft:wheat_seeds" ] || fail "the self-harvest lost the seed: $line"

if [ "$SELFTEST" = 1 ]; then
    # The counterfactual for the assertion above: if the storage were empty, the
    # self-harvest assertion would have been vacuous. It must fail here.
    say "selftest: expect the hopper pot to have harvested nothing (must fail)"
    [ "$stored" -eq 0 ] || fail "SELFTEST: the hopper pot's storage holds $stored wheat (the check is alive)"
    echo "SELFTEST unexpectedly saw an empty storage"
    exit 1
fi

say "control: a basic pot at ready does not harvest itself"
bone_meal_to_ready "$X1" "$Y" "$Z1"
ctl command "clear @s" >/dev/null
before=$(( $(count_item minecraft:wheat) + $(dropped_item minecraft:wheat) ))
ctl wait 40
after=$(( $(count_item minecraft:wheat) + $(dropped_item minecraft:wheat) ))
line=$(info "$X1" "$Y" "$Z1")
echo "basic pot after 40 ready ticks: $line; wheat $before -> $after"
[ "$(ready_of "$X1" "$Y" "$Z1")" = true ] || fail "the basic pot left ready without a click: $line"
[ "$after" -le "$before" ] || fail "the basic pot harvested itself ($before -> $after), so phase 11 proves nothing"

say "the hopper pot exports its storage into the container below"
# Place the pot on stone, then swap the stone for a chest: `ctl place` will not
# put the pot onto a container's top face, and the pot does not fall.
ctl setblock "$X6" $((Y - 1)) "$Z6" minecraft:stone >/dev/null
place_hopper "$X6" "$Y" "$Z6"
ctl setblock "$X6" $((Y - 1)) "$Z6" minecraft:chest >/dev/null || fail "cannot place the chest below"
ctl wait 3 >/dev/null
[ "$(ctl block "$X6" $((Y - 1)) "$Z6" | jq -r '.block')" = "minecraft:chest" ] \
    || fail "the block below the hopper pot is not a chest"
insert_slots "$X6" "$Y" "$Z6" minecraft:dirt minecraft:wheat_seeds 15
bone_meal_to_cap "$X6" "$Y" "$Z6"
ctl wait 40 >/dev/null
left=$(pot_storage_count "$X6" "$Y" "$Z6" minecraft:wheat)
exported=$(chest_items "$X6" $((Y - 1)) "$Z6")
echo "export: storage holds $left wheat; the chest below reads: ${exported:-nothing}"
printf '%s' "$exported" | grep -Eq 'id: ?"minecraft:wheat"' \
    || fail "the chest below the hopper pot holds no wheat (storage $left, data '${exported:-none}')"
[ "$left" -eq 0 ] || fail "the hopper pot kept $left wheat in storage while a chest was below"

say "control: a full storage pops the harvest at the pot instead of destroying it"
ctl setblock "$X7" $((Y - 1)) "$Z7" minecraft:stone >/dev/null
place_hopper "$X7" "$Y" "$Z7"
fill_storage_with_sticks "$X7" "$Y" "$Z7"
open_menu "$X7" "$Y" "$Z7" 15
filled=$(ctl screen | jq -r '[.slots[] | select(.slot >= 303 and .slot <= 314 and .item == "minecraft:stick")] | length')
ctl close >/dev/null 2>&1 || true
ctl wait 2 >/dev/null
echo "storage slots filled with sticks: $filled / 12"
[ "$filled" = 12 ] || fail "the storage holds $filled stick stacks, expected 12"
insert_slots "$X7" "$Y" "$Z7" minecraft:dirt minecraft:wheat_seeds 15
# Clear loose items around this pot first: anything counted after the harvest is
# then the harvest's own (the selftest isolation technique the notes record).
ctl command "execute in minecraft:overworld run kill @e[type=minecraft:item,x=$X7,y=$Y,z=$Z7,distance=..24]" >/dev/null
ctl wait 4 >/dev/null
bone_meal_to_cap "$X7" "$Y" "$Z7"
ctl tp "$X7.5" 101 "$(($Z7 + 1)).5" >/dev/null
ctl wait 6 >/dev/null
# The overflow is read from beside the pot. The pot's own half-block collision can
# push a player teleported into its space, so an off stand is retried a little
# further out (still inside the read radius) and logged, not failed: the counts
# below use a 24-block radius.
STAND_X=$(ctl state | jq -r '.player.position[0] | floor')
STAND_Z=$(ctl state | jq -r '.player.position[2] | floor')
if [ "$STAND_X" != "$X7" ] || [ "$STAND_Z" != "$((Z7 + 1))" ]; then
    ctl tp "$X7.5" 101 "$(($Z7 + 3)).5" >/dev/null
    ctl wait 6 >/dev/null
    STAND_X=$(ctl state | jq -r '.player.position[0] | floor')
    STAND_Z=$(ctl state | jq -r '.player.position[2] | floor')
fi
echo "  overflow reader at $STAND_X,$STAND_Z (the pot is at $X7,$Z7)"
ctl wait 40 >/dev/null
wheat=$(count_item minecraft:wheat)
dropped=$(dropped_item minecraft:wheat 24)
seeds_dropped=$(dropped_item minecraft:wheat_seeds 24)
harvested=$((wheat + dropped + seeds_dropped))
if [ "$harvested" -lt 1 ]; then
    # A failing run must name its cause: what the level holds, what the pot's own
    # storage holds, and what the server says the pot is.
    echo "  diagnostics: items near the player: $(ctl entities 24 item | jq -c '{n: (.entities | length), items: [.entities[].item.item]}')"
    echo "  diagnostics: the pot reads '$(info "$X7" "$Y" "$Z7")', block '$(ctl block "$X7" "$Y" "$Z7" | jq -r '.block // ""')'"
    echo "  diagnostics: the player holds $(ctl inventory | jq -c '.counts')"
    ctl command "data get block $X7 $Y $Z7" >/dev/null
    ctl wait 4 >/dev/null
    echo "  diagnostics: pot data: $(ctl messages 4 | jq -r '.chat[]' | grep -m1 'block data' || echo none)"
fi
# The hand still holds bone meal from the meals above: a click would fertilise.
empty_hand
open_menu "$X7" "$Y" "$Z7" 15
still=$(ctl screen | jq -r '[.slots[] | select(.slot >= 303 and .slot <= 314 and .item == "minecraft:stick")] | length')
ctl close >/dev/null 2>&1 || true
echo "overflow: wheat in inventory $wheat, wheat on the ground $dropped, seeds on the ground $seeds_dropped; stick stacks still $still"
[ "$harvested" -ge 1 ] \
    || fail "a full hopper pot destroyed its harvest (wheat $wheat, ground $dropped, seeds $seeds_dropped)"
[ "$still" = 12 ] || fail "the full-storage control lost stick stacks ($still / 12)"

say "an unknown botanypots id is refused"
if ctl give botanypots:terracotta_not_a_pot 1 >/dev/null 2>&1; then
    fail "give of an unknown botanypots id succeeded"
fi
ctl setblock "$X8" "$Y" "$Z8" botanypots:terracotta_not_a_pot >/dev/null 2>&1 || true
unknown=$(ctl block "$X8" "$Y" "$Z8" | jq -r '.block // ""')
echo "unknown id: give refused, setblock left '$unknown'"
[ "$unknown" = "minecraft:air" ] || fail "an unknown block id became $unknown"

if [ "$SELFTEST" = basic ]; then
    # The slice-1 counterfactual: the no-soil pot must have harvested.
    # Isolate the selftest from the scenario that ran before it. The harvest
    # above pops its wheat at X1 with a 10-tick pickup delay and the player
    # stands one block away, so the wheat is usually *in the inventory* by now
    # (the 2026-11-10 run read "wheat in inventory 1, wheat on the ground 0"
    # here and exited "SELFTEST unexpectedly saw 1 wheat": a contaminated
    # checker, not a no-soil harvest). Clear the inventory and the arena's
    # dropped items (Overworld, item entities within 24 blocks of the platform
    # only, so nothing unrelated is touched), then assert the pre-state is
    # clean — after that the click below is the only possible source of wheat,
    # so the verdict is the pot's and not the scenario's.
    say "selftest: isolate the player and the arena before the impossible assertion"
    ctl command "clear @s" >/dev/null || fail "SELFTEST: cannot clear the player inventory"
    ctl command "execute in minecraft:overworld run kill @e[type=minecraft:item,x=$PX,y=101,z=$PZ,distance=..24]" >/dev/null 2>&1 || true
    ctl wait 4 >/dev/null
    wheat=$(count_item minecraft:wheat)
    left=$(dropped_item minecraft:wheat)
    echo "selftest isolation: wheat in inventory $wheat, wheat on the ground $left"
    { [ "$wheat" = 0 ] && [ "$left" = 0 ]; } \
        || fail "SELFTEST: the arena is not isolated ($wheat wheat held, $left on the ground)"
    say "selftest: expect the no-soil pot to have harvested (must fail)"
    ctl interact "$X2" "$Y" "$Z2" >/dev/null || true
    ctl wait 8
    wheat=$(count_item minecraft:wheat)
    [ "$wheat" -ge 1 ] || fail "SELFTEST: the no-soil pot harvested nothing (the check is alive)"
    echo "SELFTEST unexpectedly saw $wheat wheat"
    exit 1
fi

echo "PASS: the basic pot grows soil+seed crops on its own tick (not a random tick), a wrong soil or a non-crop seed does not grow, bone meal forces growth, and a click harvests the mature crop's loot and resets; the hopper pot crafts from hopper + pot, places, joins #botanypots:botany_pots, opens its fifteen slots, harvests itself into the twelve storage slots, exports them into the container below, pops an overflow instead of destroying it, and the basic pot does not self-harvest; /botanypots info is operator-only: a level-0 LAN guest is refused while /help and /list still answer that same guest, and the world's owner still reads the pot"
