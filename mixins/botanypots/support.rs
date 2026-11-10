// Game-side glue for the botany pot slice 1.
//
// Injected into `crate::game` as `botanypots_state`; it needs the game, so it
// is not part of the standalone library (only `runtime.rs` is).
//
// The pot's block entity keeps the growth counter and the last soil/seed item
// in its saved compound, and the two container slots are the menu's soil and
// seed slots. Each server tick the counter advances while the crop's soil tag
// accepts the pot's soil; a right click harvests when it is ready (the mature
// crop's real loot table, popped at the pot), applies bone meal, or lets the
// barrel-template use path open the pot's two-slot menu.
//
// Read from Botany Pots 21.1.44 (`BotanyPotBlockEntity.tickPot`,
// `BotanyPotBlock.useItemOn`, `BasicFertilizer.apply`). See `../../FINDINGS.md`.

use horizon_client::containers::{BlockEntity, ModBlockEntity, ModContainer};
use horizon_client::hud::HudBatch;
use horizon_client::items::ItemStack;
use horizon_client::text::Text;
use horizon_world::chunk::BlockState;
use horizon_world::nbt::{Compound, JavaString, Tag};
use horizon_world::registry::BlockStateId;

use horizon_core::random::RandomSource;

use crate::game::botanypots::{
    BONE_MEAL_COOLDOWN, BONE_MEAL_MAX, BONE_MEAL_MIN, Growth, bone_meal_step, crop_for_seed, is_pot,
    required_growth_ticks, roll_count, soil_growth_modifier, total_yield,
};
use crate::game::native_hooks::NativeScreen;
use crate::game::native_server::{NativeCommand, NativeServerPlayer};
use crate::game::Game;

/// The menu type the pot's content mod declares (`data/botanypots/horizon/menu/`).
pub const POT_MENU: &str = "botanypots:basic_pot_menu";
/// The block entity's saved keys.
const KEY_GROWTH: &str = "growth";
const KEY_SOIL: &str = "soil";
const KEY_SEED: &str = "seed";
const KEY_BONE_MEAL: &str = "bone_meal";
/// The two container slots: soil then seed (`AbstractBotanyPotBlockEntity`).
const SOIL_SLOT: usize = 0;
const SEED_SLOT: usize = 1;
const SLOT_COUNT: usize = 2;

// ---------------------------------------------------------------------------
// Declaration hooks
// ---------------------------------------------------------------------------

/// Give each botany pot a block entity (`native_block_entity`, API 15).
#[allow(private_interfaces)]
pub fn on_block_entity(block: &str, entity: &mut Option<(String, Compound)>) {
    if is_pot(block) {
        *entity = Some((block.to_owned(), Compound::new()));
    }
}

/// The pots tick (`native_block_entity_ticks`, API 15).
#[allow(private_interfaces)]
pub fn on_block_entity_ticks(block: &str, ticks: &mut bool) {
    if is_pot(block) {
        *ticks = true;
    }
}

/// Two player-only slots and the pot's two-slot menu (`native_block_entity_container`,
/// API 16/17). Upstream refuses every hopper insert (`canPlaceItemThroughFace`
/// is false) and only a hopper pot lets the bottom face take the storage slots;
/// this slice has neither, so no face reaches the slots.
#[allow(private_interfaces)]
pub fn on_container(block: &str, container: &mut Option<ModContainer>) {
    if !is_pot(block) {
        return;
    }
    *container = Some(ModContainer {
        slots: SLOT_COUNT,
        faces: std::array::from_fn(|_| Vec::new()),
        inputs: Vec::new(),
        outputs: Vec::new(),
        menu: Some(POT_MENU.to_owned()),
    });
}

// ---------------------------------------------------------------------------
// The growth tick
// ---------------------------------------------------------------------------

/// The block entity's tick (`native_block_entity_tick`, API 15): advance the
/// crop while its soil tag accepts the pot's soil, cap at what it needs, and
/// publish the progress in the menu's two data slots.
#[allow(private_interfaces)]
pub fn on_tick(game: &mut Game<'_>, pos: [i32; 3], entity: &mut ModBlockEntity) {
    if !is_pot(&entity.id) {
        return;
    }
    let _ = pos;
    if entity.items.len() < SLOT_COUNT {
        entity.items.resize(SLOT_COUNT, None);
    }
    let soil = entity.items[SOIL_SLOT].as_ref().map(|stack| stack.item.clone());
    let seed = entity.items[SEED_SLOT].as_ref().map(|stack| stack.item.clone());
    let mut growth = Growth::from_ticks(nbt_u32(&entity.nbt, KEY_GROWTH));
    let mut cooldown = nbt_u32(&entity.nbt, KEY_BONE_MEAL);
    // A different soil or seed starts the crop over (`onSoilChanged`/`onSeedChanged`).
    if nbt_string(&entity.nbt, KEY_SOIL).as_deref() != soil.as_deref()
        || nbt_string(&entity.nbt, KEY_SEED).as_deref() != seed.as_deref()
    {
        set_string(&mut entity.nbt, KEY_SOIL, soil.as_deref());
        set_string(&mut entity.nbt, KEY_SEED, seed.as_deref());
        growth.reset();
        cooldown = 0;
    }
    if cooldown > 0 {
        cooldown -= 1;
    }
    let crop = seed.as_deref().and_then(crop_for_seed);
    let soil_ok = crop.is_some_and(|crop| {
        soil.as_deref()
            .is_some_and(|item| item_in_tag(game, item, crop.soil_tag))
    });
    let required = crop.map_or(0, |crop| {
        required_growth_ticks(
            crop.grow_time,
            soil.map_or(0.0, |soil| soil_growth_modifier(&soil)),
        )
    });
    if soil_ok && required > 0 {
        growth.tick(required);
    }
    entity
        .nbt
        .insert(JavaString::from(KEY_GROWTH), Tag::Int(growth.ticks() as i32));
    entity
        .nbt
        .insert(JavaString::from(KEY_BONE_MEAL), Tag::Int(cooldown as i32));
    let data = vec![growth.ticks() as i32, required as i32];
    if entity.data != data {
        entity.data = data;
    }
}

// ---------------------------------------------------------------------------
// Client side: the screen
// ---------------------------------------------------------------------------

/// The pot's two-slot screen layout (`native_screen`, API 19): the soil slot
/// and the seed slot, as `BotanyPotMenu` lays them out.
#[allow(private_interfaces)]
pub fn on_screen(block: &str, screen: &mut Option<NativeScreen>) {
    if !is_pot(block) {
        return;
    }
    *screen = Some(NativeScreen {
        width: 176.0,
        height: 166.0,
        slots: vec![Some([80.0, 48.0]), Some([80.0, 22.0])],
        inventory_y: 84.0,
        inventory_x: 8.0,
        own_labels: false,
        // Horizon draws the plain panel and the slot frames; the pot has no
        // GUI texture in this slice.
        own_background: false,
    });
}

/// Draws the growth progress over the pot screen (`native_screen_draw`, API 19):
/// the menu's data slots are `[growth, required]`.
#[allow(private_interfaces)]
pub fn on_screen_draw(
    game: &Game<'_>,
    block: &str,
    data: &[i32],
    batch: &mut HudBatch,
    origin: [f32; 2],
) {
    if !is_pot(block) {
        return;
    }
    let growth = data.first().copied().unwrap_or(0);
    let required = data.get(1).copied().unwrap_or(0);
    let text = if required > 0 && growth >= required {
        "Ready".to_owned()
    } else if required > 0 {
        format!("{growth} / {required}")
    } else {
        "-".to_owned()
    };
    game.native_text(
        batch,
        &text,
        [origin[0] + 8.0, origin[1] + 58.0],
        0x404040,
        false,
    );
}

// ---------------------------------------------------------------------------
// Player interaction
// ---------------------------------------------------------------------------

/// Right click (`native_right_click_block`, API 21): harvest a ready pot, apply
/// bone meal, or leave the click to the barrel template's use path, which opens
/// the pot's menu. A pot with nothing to harvest and no bone meal in hand opens
/// its menu, as upstream's `useItemOn` falls through to `openMenu`.
#[allow(private_interfaces)]
pub fn on_right_click(
    game: &mut Game<'_>,
    pos: [i32; 3],
    _face: [i32; 3],
    canceled: &mut bool,
) {
    if !is_pot(&game.native_block(pos)) {
        return;
    }
    let state = read_pot(game, pos);
    let Some(state) = state else {
        return;
    };
    if state.ready {
        harvest(game, pos, &state);
        *canceled = true;
        return;
    }
    let held = game.held().cloned();
    if held.as_ref().is_some_and(|stack| &*stack.item == BONE_MEAL) {
        apply_bone_meal(game, pos, &state, held.as_ref());
        *canceled = true;
    }
}

fn apply_bone_meal(
    game: &mut Game<'_>,
    pos: [i32; 3],
    state: &PotState,
    held: Option<&ItemStack>,
) {
    if held.is_none_or(|stack| stack.count == 0) {
        return;
    }
    if state.crop.is_none() || state.bone_meal_cooldown > 0 {
        return;
    }
    let amount = bone_meal_amount(game);
    let Some(next) = bone_meal_step(state.growth, state.required, amount) else {
        return;
    };
    let mut guard = lock_state(game, pos);
    guard.growth = next;
    guard.bone_meal_cooldown = BONE_MEAL_COOLDOWN;
    drop(guard);
    let creative = game
        .native_acting_player()
        .is_some_and(|player| player.game_mode == 1);
    if !creative {
        game.native_take_items(BONE_MEAL, 1);
    }
}

fn harvest(game: &mut Game<'_>, pos: [i32; 3], state: &PotState) {
    let Some(crop) = state.crop else {
        return;
    };
    let Some(mature) = mature_state(game, crop.block, crop.mature_age) else {
        return;
    };
    let dimension = game.native_dimension().to_owned();
    let roll = game
        .native_level_random(&dimension)
        .map_or(0.0, RandomSource::next_float);
    let rolls = roll_count(total_yield(crop, 0.0, 0.0), roll);
    for _ in 0..rolls {
        let drops = game.block_loot_at(pos, mature, None, None);
        for drop in drops {
            game.pop_resource(pos, drop);
        }
    }
    let mut guard = lock_state(game, pos);
    guard.growth = 0;
    guard.bone_meal_cooldown = 0;
}

// ---------------------------------------------------------------------------
// The `/botanypots info` readout
// ---------------------------------------------------------------------------

/// The readout command (`native_register_commands`, API 8).
#[allow(private_interfaces)]
pub fn on_register_commands(commands: &mut Vec<NativeCommand>) {
    commands.push(NativeCommand::new("botanypots info"));
}

/// `/botanypots info <x> <y> <z>` (`native_perform_command`, API 8): the pot's
/// growth, required ticks and slots, for the harness and for players.
#[allow(private_interfaces)]
pub fn on_perform_command(
    game: &mut Game<'_>,
    _player: &NativeServerPlayer,
    command: &str,
    ran: &mut bool,
) {
    let words: Vec<&str> = command.split_whitespace().collect();
    if words.first() != Some(&"botanypots") {
        return;
    }
    *ran = true;
    let parsed = (2..5)
        .map(|index| words.get(index).and_then(|word| word.parse::<i32>().ok()))
        .collect::<Option<Vec<i32>>>();
    let Some(parsed) = parsed.filter(|_| words.get(1) == Some(&"info")) else {
        game.native_feedback(Text::literal(
            "usage: /botanypots info <x> <y> <z>",
        ));
        return;
    };
    let pos = [parsed[0], parsed[1], parsed[2]];
    let block = game.native_block(pos);
    let line = match read_pot(game, pos) {
        Some(state) => format!(
            "{block}: growth={}/{} soil={} seed={} ready={}",
            state.growth,
            state.required,
            state.soil.as_deref().unwrap_or("none"),
            state.seed.as_deref().unwrap_or("none"),
            state.ready
        ),
        None => format!("{block}: not a botany pot"),
    };
    game.native_feedback(Text::literal(line));
}

// ---------------------------------------------------------------------------
// Shared reads
// ---------------------------------------------------------------------------

const BONE_MEAL: &str = "minecraft:bone_meal";

/// What the pot's block entity says right now.
struct PotState {
    growth: u32,
    required: u32,
    ready: bool,
    bone_meal_cooldown: u32,
    soil: Option<String>,
    seed: Option<String>,
    crop: Option<&'static crate::game::botanypots::Crop>,
}

fn read_pot(game: &Game<'_>, pos: [i32; 3]) -> Option<PotState> {
    let entity = match game.world.block_entities.get(&(pos[0], pos[1], pos[2])) {
        Some(BlockEntity::Mod(entity)) if is_pot(&entity.id) => entity,
        _ => return None,
    };
    let soil = item_id(entity, SOIL_SLOT);
    let seed = item_id(entity, SEED_SLOT);
    let crop = seed.as_deref().and_then(crop_for_seed);
    let soil_ok = crop.is_some_and(|crop| {
        soil.as_deref()
            .is_some_and(|item| item_in_tag(game, item, crop.soil_tag))
    });
    let required = crop.map_or(0, |crop| {
        required_growth_ticks(
            crop.grow_time,
            soil.as_deref().map_or(0.0, soil_growth_modifier),
        )
    });
    let growth = Growth::from_ticks(nbt_u32(&entity.nbt, KEY_GROWTH));
    Some(PotState {
        growth: growth.ticks(),
        required,
        ready: soil_ok && required > 0 && growth.is_ready(required),
        bone_meal_cooldown: nbt_u32(&entity.nbt, KEY_BONE_MEAL),
        soil,
        seed,
        crop,
    })
}

/// A write guard over the pot's block entity, through the API 18 helper so the
/// chunk is marked and comparators hear it. Panics never leave a stale local
/// copy: the closure writes straight into the entity.
struct PotGuard<'a, 'g> {
    game: &'a mut Game<'g>,
    pos: [i32; 3],
    growth: u32,
    bone_meal_cooldown: u32,
}

impl Drop for PotGuard<'_, '_> {
    fn drop(&mut self) {
        let (growth, cooldown) = (self.growth, self.bone_meal_cooldown);
        let _ = self.game.native_with_mod_block_entity(self.pos, |entity| {
            entity
                .nbt
                .insert(JavaString::from(KEY_GROWTH), Tag::Int(growth as i32));
            entity.nbt.insert(
                JavaString::from(KEY_BONE_MEAL),
                Tag::Int(cooldown as i32),
            );
        });
    }
}

fn lock_state<'a, 'g>(game: &'a mut Game<'g>, pos: [i32; 3]) -> PotGuard<'a, 'g> {
    let (growth, cooldown) = match read_pot(game, pos) {
        Some(state) => (state.growth, state.bone_meal_cooldown),
        None => (0, 0),
    };
    PotGuard {
        game,
        pos,
        growth,
        bone_meal_cooldown: cooldown,
    }
}

fn item_id(entity: &ModBlockEntity, slot: usize) -> Option<String> {
    entity
        .items
        .get(slot)
        .and_then(|stack| stack.as_ref())
        .filter(|stack| stack.count > 0)
        .map(|stack| stack.item.to_string())
}

/// Whether `item` is in the server's merged item tag `tag` (the soil tags are
/// carried content; `native_server_item_in_tag` is API 28's read, called here
/// from the pot's own server-side hooks).
fn item_in_tag(game: &Game<'_>, item: &str, tag: &str) -> bool {
    let stack = ItemStack {
        item: item.into(),
        count: 1,
        damage: 0,
        extra: None,
    };
    game.native_server_item_in_tag(&stack, tag).unwrap_or(false)
}

/// The mature crop's state (`Block.getStateForAge(maxAge)`), for the loot roll.
fn mature_state(game: &Game<'_>, block: &str, age: u32) -> Option<BlockStateId> {
    let mut state = BlockState {
        name: block.to_owned(),
        properties: horizon_world::chunk::BlockProperties::default(),
    };
    state.properties.insert("age".to_owned(), age.to_string());
    game.pack.assets.registry.resolve(&state).ok()
}

/// One bone meal's growth, drawn from the level's own random (`RangedGrowthAmount`:
/// `Mth.nextInt(level.random, min, max)`).
fn bone_meal_amount(game: &mut Game<'_>) -> u32 {
    let dimension = game.native_dimension().to_owned();
    let Some(random) = game.native_level_random(&dimension) else {
        return BONE_MEAL_MIN;
    };
    let span = BONE_MEAL_MAX - BONE_MEAL_MIN + 1;
    BONE_MEAL_MIN
        + u32::try_from(
            random
                .next_int_bound(i32::try_from(span).unwrap_or(i32::MAX))
                .unwrap_or(0),
        )
        .unwrap_or(0)
}

fn nbt_u32(tag: &Compound, key: &str) -> u32 {
    match tag.get(&JavaString::from(key)) {
        Some(Tag::Int(value)) => u32::try_from(*value).unwrap_or(0),
        Some(Tag::Float(bits)) => f32::from_bits(*bits).max(0.0) as u32,
        _ => 0,
    }
}

fn nbt_string(tag: &Compound, key: &str) -> Option<String> {
    match tag.get(&JavaString::from(key)) {
        Some(Tag::String(value)) if !value.0.is_empty() => value.to_string().ok(),
        _ => None,
    }
}

fn set_string(tag: &mut Compound, key: &str, value: Option<&str>) {
    tag.insert(
        JavaString::from(key),
        Tag::String(JavaString::from(value.unwrap_or(""))),
    );
}
