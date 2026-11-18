#!/usr/bin/env bash
# In-game check for Botany Pots slice 1: the botany pot block.
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
#   8. an empty-hand click on the reset pot harvests nothing.
#
# SELFTEST=1 runs the same scenario but asserts the no-soil pot DID harvest:
# that must fail (exit 1), proving the growth/harvest assertions are not vacuous.
#
# SDK layout (0.2.0): GAME must be a **launcher-built** horizon-client carrying
# this package (`horizon-launcher native-build <port> … --trust-native-code`),
# because the mod's code is compiled into the game. The package also carries the
# content, so no `--dev-mod` is needed; DEV_MOD=1 adds the delivered
# `botanypots.hmod` as one anyway (for a build that only carries the code).
#
# CONTROL_GAME=<an unmodded launcher build> runs one extra leg first: the pot id
# must be unknown there and the `/botanypots` command absent, which is what makes
# the scenario's positives non-vacuous.
#
# The 0.1.0 EMBEDDED legs (the bundle writing its content out to
# `.horizon-cache`, and its control) retired with the `.hnmod` container: one
# package now holds both halves. Their runs stay in
# `../_shared/evidence/botanypots/e2e-embedded*.log`; SELFTEST=1 and
# CONTROL_GAME remain the two counterfactuals.
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
SELFTEST=${SELFTEST:-0}
# DEV_MOD=1 also hands the delivered package to the game with `--dev-mod`.
DEV_MOD=${DEV_MOD:-0}
WORLD=BotanyPotsE2E
CONTROL_WORLD=BotanyPotsControl

POT=botanypots:terracotta_botany_pot

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
fail() { echo "FAIL: $*" >&2; exit 1; }
say() { echo "== $* =="; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
dropped_item() {
    ctl entities 10 item \
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

open_menu() { # x y z
    ctl interact "$1" "$2" "$3" >/dev/null || fail "the click did not open the pot menu"
    ctl wait-for screen container --timeout 10 >/dev/null \
        || fail "the pot did not open a menu (screen=$(ctl state | jq -r '.screen // ""'))"
    local slots
    slots=$(ctl screen | jq '[.slots[] | select(.slot >= 300)] | length' 2>/dev/null || echo 0)
    [ "$slots" = 2 ] || fail "the pot menu shows $slots slots, expected 2"
}

insert_slots() { # x y z soil seed
    ctl command "clear @s" >/dev/null
    ctl give "$4" 1 >/dev/null || fail "cannot give $4"
    ctl wait 2 >/dev/null
    open_menu "$1" "$2" "$3"
    echo "menu slots: 2 (soil, seed)"
    put_in_slot 300 "$4"
    ctl close >/dev/null 2>&1 || true
    ctl wait 3 >/dev/null
    ctl command "clear @s" >/dev/null
    ctl give "$5" 1 >/dev/null || fail "cannot give $5"
    ctl wait 2 >/dev/null
    open_menu "$1" "$2" "$3"
    put_in_slot 301 "$5"
    ctl close >/dev/null 2>&1 || true
    ctl wait 4 >/dev/null
}

cleanup() {
    local status=$?
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
# pot id must be unknown there and no `/botanypots` command may answer; if either
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
        ctl wait 6
        local name held reply
        name=$(ctl block "$((x-2))" 102 "$((z+1))" | jq -r '.block // ""')
        held=$(count_item botanypots:terracotta_botany_pot)
        echo "  placed block: $name; pots in inventory: $held"
        [ "$name" = "minecraft:air" ] || fail "the control game holds $name, so the pot id was known"
        [ "$held" = 0 ] || fail "the control game holds $held pot items, so the pot id was known"
        ctl chat "/botanypots info $((x-2)) 102 $((z+1))" >/dev/null
        ctl wait 4
        reply=$(ctl messages 6 | jq -r '.chat[]' | grep -m1 "botanypots" || true)
        echo "  native command reply: ${reply:-none}"
        [ -z "$reply" ] || fail "the control game answered a /botanypots command: $reply"
        echo "  without the package: no pot block, no pot item, no pot command"
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
[ "$(growth_of "$X1" "$Y" "$Z1")" -lt 40 ] || fail "a freshly planted pot already grew"

say "the growth tick advances in dirt"
ctl wait 40
after=$(growth_of "$X1" "$Y" "$Z1")
echo "growth after 40 ticks: $after / 1200"
[ "$after" -ge 20 ] || fail "the pot grew $after ticks in 40, expected at least 20"
[ "$after" -le 60 ] || fail "the pot grew $after ticks in 40, expected at most 60"

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
# A second meal reaches the required - 20 cap; a right click on a ready pot
# harvests instead of fertilising, so stop as soon as it is ready.
if [ "$(ready_of "$X1" "$Y" "$Z1")" != true ]; then
    ctl interact "$X1" "$Y" "$Z1" >/dev/null || fail "bone meal click failed"
    ctl wait 25
    echo "after bone meal 2: $(info "$X1" "$Y" "$Z1")"
fi
ctl wait 30
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
[ "$(growth_of "$X1" "$Y" "$Z1")" -lt 40 ] || fail "the harvest did not reset growth: $line"
[ "$(seed_of "$X1" "$Y" "$Z1")" = "minecraft:wheat_seeds" ] || fail "the harvest lost the seed: $line"

say "an empty click on the reset pot harvests nothing"
before=$(( $(count_item minecraft:wheat) + $(dropped_item minecraft:wheat) ))
ctl interact "$X1" "$Y" "$Z1" >/dev/null || fail "the reset-pot click failed"
ctl wait 8
after=$(( $(count_item minecraft:wheat) + $(dropped_item minecraft:wheat) ))
echo "second click wheat: $before -> $after"
[ "$after" -le "$before" ] || fail "a young pot harvested wheat: $before -> $after"

if [ "$SELFTEST" = 1 ]; then
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

echo "PASS: the pot grows soil+seed crops on its own tick (not a random tick), a wrong soil or a non-crop seed does not grow, bone meal forces growth, and harvest pops the mature crop's loot and resets"
