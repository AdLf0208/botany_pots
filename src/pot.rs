//! The botany pot's glue: its block entity Part, the block's container and click
//! Part, the menu and its readout, the growth tick, the harvest and the
//! `/botanypots info` readout.
//!
//! Every rule lives in [`crate::runtime`] (the retired `.hnmod`'s `runtime.rs`,
//! byte-identical); this file reads the game, calls it and writes the result
//! back. Its tests pin what it *declares* (two slots and the menu, no hopper
//! face), that the saved compound reads back, and the exact readout line.

use mod_api::{
    BlockClick, BlockEntityEvent, BlockEntityPart, BlockEntityRef, BlockEntityTickEvent,
    BlockEntityTickReply, BlockEntityTicksEvent, BlockEntityTypeKey, BlockPart, ClientHost,
    Compound, Host, HostTransaction, Identifier, InteractionResult, ItemKey, ItemPlace,
    ItemResource, ItemStack, LevelRef, LevelSide, ModContainer, RandomSource, Registrar, Screen,
    ScreenDrawEvent, ScreenEvent, ServerHost, Tag, UseItemOnEvent, UseWithoutItemEvent,
};

use crate::runtime::{
    BONE_MEAL_COOLDOWN, BONE_MEAL_MAX, BONE_MEAL_MIN, Crop, Growth, bone_meal_step, crop_for_seed,
    is_pot, required_growth_ticks, roll_count, soil_growth_modifier, total_yield,
};

/// The one pot this slice registers.
pub(crate) const POT: &str = "botanypots:terracotta_botany_pot";

/// The block entity type's path, in this mod's namespace.
const POT_TYPE: &str = "terracotta_botany_pot";

/// The menu type the content declares (`data/botanypots/horizon/menu/`).
pub(crate) const MENU: &str = "botanypots:basic_pot_menu";

/// The two container slots, soil then seed (`AbstractBotanyPotBlockEntity`).
const SOIL_SLOT: usize = 0;
const SEED_SLOT: usize = 1;
const SLOT_COUNT: usize = 2;

/// The block entity's saved keys.
const KEY_GROWTH: &str = "growth";
const KEY_SOIL: &str = "soil";
const KEY_SEED: &str = "seed";
const KEY_BONE_MEAL: &str = "bone_meal";

/// The fertilizer item this slice knows (`data/.../fertilizer/bone_meal.json`).
const BONE_MEAL: &str = "minecraft:bone_meal";

// ---------------------------------------------------------------------------
// Declarations
// ---------------------------------------------------------------------------

/// The block entity type declared for the pot, built in `Hooks::register`.
pub(crate) fn declare(registrar: &mut dyn Registrar) -> BlockEntityTypeKey {
    registrar
        .block_entity_type(POT_TYPE)
        .blocks(&[POT_TYPE])
        .build()
}

/// The pot's container: two slots nothing reaches — soil 0, seed 1 — and the pot
/// menu. Upstream refuses every hopper face (`canPlaceItemThroughFace` is false)
/// and only a hopper pot lets the bottom face reach the storage slots; this slice
/// has neither, so no face reaches these slots.
pub(crate) fn container() -> ModContainer {
    ModContainer {
        slots: SLOT_COUNT,
        faces: std::array::from_fn(|_| Vec::new()),
        inputs: Vec::new(),
        outputs: Vec::new(),
        menu: Some(MENU.to_owned()),
    }
}

/// The pot's menu: upstream's 176 x 166 panel with the soil slot and the seed
/// slot, as `BotanyPotMenu` lays them out.
pub(crate) fn menu() -> Screen {
    Screen {
        width: 176.0,
        height: 166.0,
        slots: vec![Some([80.0, 48.0]), Some([80.0, 22.0])],
        inventory_y: 84.0,
        inventory_x: 8.0,
        own_labels: false,
        own_background: false,
        ..Screen::default()
    }
}

// ---------------------------------------------------------------------------
// The saved state
// ---------------------------------------------------------------------------

/// What the pot's block entity saves.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct Saved {
    pub(crate) growth: u32,
    pub(crate) bone_meal: u32,
    pub(crate) soil: Option<String>,
    pub(crate) seed: Option<String>,
}

/// The pot saved in a block entity's compound; a fresh one is empty.
pub(crate) fn read(saved: &Compound) -> Saved {
    Saved {
        growth: saved_u32(saved, KEY_GROWTH),
        bone_meal: saved_u32(saved, KEY_BONE_MEAL),
        soil: saved_string(saved, KEY_SOIL),
        seed: saved_string(saved, KEY_SEED),
    }
}

/// Write the pot back, under upstream's keys. An empty slot saves the empty
/// string, the shape 0.1.0 wrote.
pub(crate) fn write(saved: &mut Compound, state: &Saved) {
    saved.insert(KEY_GROWTH.into(), Tag::Int(int_of(state.growth)));
    saved.insert(KEY_BONE_MEAL.into(), Tag::Int(int_of(state.bone_meal)));
    for (key, value) in [(KEY_SOIL, &state.soil), (KEY_SEED, &state.seed)] {
        saved.insert(
            key.into(),
            Tag::String(value.as_deref().unwrap_or("").into()),
        );
    }
}

/// A saved counter, 0 when absent or of another type. An older save may hold a
/// float (`growthTime` was a float upstream), so read that too.
fn saved_u32(saved: &Compound, key: &str) -> u32 {
    match saved.get(&key.into()) {
        Some(Tag::Int(value)) => u32::try_from(*value).unwrap_or(0),
        Some(Tag::Float(bits)) => f32::from_bits(*bits).max(0.0) as u32,
        _ => 0,
    }
}

/// A saved item id; the empty string reads as nothing.
fn saved_string(saved: &Compound, key: &str) -> Option<String> {
    let Some(Tag::String(value)) = saved.get(&key.into()) else {
        return None;
    };
    let text = value.to_string_lossy();
    (!text.is_empty()).then_some(text)
}

/// A counter as the int the menu's 16-bit data slots take.
fn int_of(value: u32) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

// ---------------------------------------------------------------------------
// Reading the pot
// ---------------------------------------------------------------------------

/// What a pot holds and what that means: its crop, the ticks it needs, whether it
/// grows and whether it is ready.
struct Reading {
    crop: Option<&'static Crop>,
    required: u32,
    grows: bool,
    ready: bool,
}

/// The crop in the seed slot and the soil's growth modifier, as the tick and the
/// readout both need them.
fn reading(host: &dyn Host, soil: Option<ItemKey>, seed: Option<ItemKey>, growth: u32) -> Reading {
    let seed_id = seed.map(|key| key.id(host));
    let crop = seed_id.as_deref().and_then(crop_for_seed);
    let soil_modifier = soil.map_or(0.0, |key| soil_growth_modifier(&key.id(host)));
    let required = crop.map_or(0, |crop| {
        required_growth_ticks(crop.grow_time, soil_modifier)
    });
    let soil_ok =
        crop.is_some_and(|crop| soil.is_some_and(|key| item_in_tag(host, key, crop.soil_tag)));
    let grows = soil_ok && required > 0;
    Reading {
        crop,
        required,
        grows,
        ready: grows && Growth::from_ticks(growth).is_ready(required),
    }
}

/// The item key a container slot holds, if any.
fn slot_key(slot: Option<&Option<ItemStack>>) -> Option<ItemKey> {
    slot.and_then(Option::as_ref).map(ItemStack::item)
}

/// The item key the block entity's slot `slot` holds, if any.
fn entity_slot_key(host: &dyn Host, entity: &BlockEntityRef, slot: usize) -> Option<ItemKey> {
    let slot = u32::try_from(slot).ok()?;
    entity
        .item_slot(host, slot)
        .ok()
        .flatten()
        .map(|stack| stack.item())
}

/// Whether `item` is in the server's merged item tag `tag` (the soil tags are
/// carried content; unknown tags answer false, as the 0.1.0 helper did).
fn item_in_tag(host: &dyn Host, item: ItemKey, tag: &str) -> bool {
    let Ok(tag) = Identifier::parse(tag) else {
        return false;
    };
    let Some(key) = host.tags().key(&tag) else {
        return false;
    };
    host.tags().is_in_tag(item, key).unwrap_or(false)
}

// ---------------------------------------------------------------------------
// Parts
// ---------------------------------------------------------------------------

/// The pot's clicks: harvest, bone meal, or let the barrel template open the menu.
pub(crate) struct PotClick;

#[mod_api::horizon_part]
impl BlockPart for PotClick {
    /// The pot's own `useItemOn`: a ready pot harvests, a pot holding no crop or
    /// on bone-meal cooldown falls through to the template's use (the menu), and
    /// bone meal in hand forces growth.
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        let click = event.click;
        let pos = click.pos;
        let level = host.level(host.dimension())?;
        let entity = host.block_entity(level, pos)?;
        let saved = read(&entity.data(&*host)?);
        let soil = entity_slot_key(&*host, &entity, SOIL_SLOT);
        let seed = entity_slot_key(&*host, &entity, SEED_SLOT);
        let reading = reading(&*host, soil, seed, saved.growth);
        if reading.ready {
            harvest(host, pos, reading.crop?);
            return Some(InteractionResult::Success);
        }
        let held = click.stack?;
        if held.item().id(&*host) != BONE_MEAL {
            return None;
        }
        let amount = bone_meal_amount(host, level);
        let next = bone_meal_step(saved.growth, reading.required, amount)?;
        apply_bone_meal(host, level, click, next).then_some(InteractionResult::Success)
    }

    /// The empty-hand click: a ready pot harvests, everything else is the
    /// template's (`openMenu`).
    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        let pos = event.click.pos;
        let level = host.level(host.dimension())?;
        let entity = host.block_entity(level, pos)?;
        let saved = read(&entity.data(&*host)?);
        let soil = entity_slot_key(&*host, &entity, SOIL_SLOT);
        let seed = entity_slot_key(&*host, &entity, SEED_SLOT);
        let reading = reading(&*host, soil, seed, saved.growth);
        if !reading.ready {
            return None;
        }
        harvest(host, pos, reading.crop?);
        Some(InteractionResult::Success)
    }
}

/// The pot's block entity: its saved state, its tick, its menu and readout.
pub(crate) struct PotEntity;

#[mod_api::horizon_part]
impl BlockPart for PotEntity {}

#[mod_api::horizon_part]
impl BlockEntityPart for PotEntity {
    /// A fresh pot starts with an empty compound (`newBlockEntity`).
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: the pot ticks. Never clear a value an earlier mod
    /// set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: a changed soil or seed starts the crop over, the bone-meal
    /// cooldown counts down, the growth advances while the crop's soil tag accepts
    /// the pot's soil, and the menu's two data slots carry growth and required.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let resized = event.entity.items.len() != SLOT_COUNT;
        if resized {
            event.entity.items.resize(SLOT_COUNT, None);
        }
        let before = read(&event.entity.nbt);
        let soil = slot_key(event.entity.items.first());
        let seed = slot_key(event.entity.items.get(SEED_SLOT));
        let soil_id = soil.map(|key| key.id(&*host));
        let seed_id = seed.map(|key| key.id(&*host));
        let mut state = before.clone();
        // A different soil or seed starts the crop over (`onSoilChanged`/`onSeedChanged`).
        if state.soil != soil_id || state.seed != seed_id {
            state.soil = soil_id;
            state.seed = seed_id;
            state.growth = 0;
            state.bone_meal = 0;
        }
        state.bone_meal = state.bone_meal.saturating_sub(1);
        let reading = reading(&*host, soil, seed, state.growth);
        if reading.grows {
            let mut growth = Growth::from_ticks(state.growth);
            growth.tick(reading.required);
            state.growth = growth.ticks();
        }
        let data = vec![int_of(state.growth), int_of(reading.required)];
        let data_changed = event.entity.data != data;
        let changed = resized || data_changed || state != before;
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
            return;
        }
        write(&mut event.entity.nbt, &state);
        if data_changed {
            event.entity.data = data;
        }
    }

    /// The pot menu's layout.
    fn screen(&self, _host: &dyn Host, _event: &mut ScreenEvent<'_>) -> Option<Screen> {
        Some(menu())
    }

    /// The growth readout, from the menu's data slots `[growth, required]`
    /// (API 19's `native_screen_draw`).
    fn screen_draw(&self, _host: &dyn ClientHost, event: &mut ScreenDrawEvent<'_>) {
        let growth = event.data.first().copied().unwrap_or(0);
        let required = event.data.get(1).copied().unwrap_or(0);
        let text = if required > 0 && growth >= required {
            "Ready".to_owned()
        } else if required > 0 {
            format!("{growth} / {required}")
        } else {
            "-".to_owned()
        };
        let [x, y] = event.origin;
        event
            .draw
            .text(&text, [x + 8.0, y + 58.0], 0xFF40_4040, false);
    }
}

// ---------------------------------------------------------------------------
// Bone meal and harvest
// ---------------------------------------------------------------------------

/// One bone meal's growth, drawn from the level's own random (`RangedGrowthAmount`:
/// `Mth.nextInt(level.random, min, max)`).
fn bone_meal_amount(host: &mut dyn ServerHost, level: LevelRef) -> u32 {
    let Ok(span) = i32::try_from(BONE_MEAL_MAX - BONE_MEAL_MIN + 1) else {
        return BONE_MEAL_MIN;
    };
    level
        .with_random(host, |random| random.next_int_bound(span).unwrap_or(0))
        .map_or(BONE_MEAL_MIN, |drawn| {
            BONE_MEAL_MIN + u32::try_from(drawn).unwrap_or(0)
        })
}

/// Apply one bone meal: the growth moves to `next` and the cooldown restarts,
/// and one meal leaves the clicking hand. Both writes are one transaction, so a
/// hand that gives nothing grows nothing. A creative player's hand keeps its meal
/// (`extract` gives without losing any, as `forInfiniteMaterials` does).
fn apply_bone_meal(
    host: &mut dyn ServerHost,
    level: LevelRef,
    click: &BlockClick<'_>,
    next: u32,
) -> bool {
    let Some(entity) = host.block_entity(level, click.pos) else {
        return false;
    };
    let Some(resource) = click.stack.map(ItemResource::of) else {
        return false;
    };
    let place = ItemPlace::PlayerHand {
        player: click.player,
        hand: click.hand,
    };
    let mut patch = Compound::new();
    patch.insert(KEY_GROWTH.into(), Tag::Int(int_of(next)));
    patch.insert(KEY_BONE_MEAL.into(), Tag::Int(int_of(BONE_MEAL_COOLDOWN)));
    host.transaction(|host, tx| {
        if place.extract(host, tx, &resource, 1) == 0 {
            return Err(());
        }
        entity.merge_data(host, patch).map_err(|_| ())?;
        Ok(())
    })
    .is_ok()
}

/// Harvest a ready pot: roll the mature crop's loot table once per yield roll,
/// pop each stack at the pot, and reset the growth (`BlockStateDrops`).
///
/// Recorded gap: the SDK's `LevelRef::roll_loot` gives a loot context with the
/// origin, the tool and the entity but **no block state**, so a 26.3 table whose
/// pool is gated on `match_block {state: {age: "7"}}` (every vanilla crop's
/// produce) cannot see the mature state. The port therefore adds the crop block's
/// own item once per roll unless the roll already gave it, which is the produce
/// the state condition would have allowed; the table still supplies the seed
/// pools, and the count of seeds is the table's own roll.
fn harvest(host: &mut dyn ServerHost, pos: [i32; 3], crop: &'static Crop) {
    let Some(level) = host.level(host.dimension()) else {
        return;
    };
    let roll = level
        .with_random(host, |random| random.next_float())
        .unwrap_or(0.0);
    let rolls = roll_count(total_yield(crop, 0.0, 0.0), roll);
    let table = loot_table_of(crop.block);
    let produce = produce_item(&*host, crop.block);
    let origin = [
        f64::from(pos[0]) + 0.5,
        f64::from(pos[1]),
        f64::from(pos[2]) + 0.5,
    ];
    for _ in 0..rolls {
        let rolled = level
            .roll_loot(host, &table, origin, None, None)
            .ok()
            .flatten()
            .unwrap_or_default();
        let gave_produce =
            produce.is_some_and(|item| rolled.iter().any(|stack| stack.item() == item));
        for stack in rolled {
            let _ = level.pop_resource(host, pos, stack);
        }
        if let Some(item) = produce.filter(|_| !gave_produce) {
            let _ = level.pop_resource(host, pos, ItemStack::of(item));
        }
    }
    reset(host, level, pos);
}

/// A block's loot table id: `minecraft:wheat` -> `minecraft:blocks/wheat`
/// (`LootTable` ids are `<namespace>:blocks/<path>`).
fn loot_table_of(block: &str) -> String {
    match block.split_once(':') {
        Some((namespace, path)) => format!("{namespace}:blocks/{path}"),
        None => format!("minecraft:blocks/{block}"),
    }
}

/// The item a crop block is worth (`Block.asItem`): wheat for `minecraft:wheat`,
/// beetroot for `minecraft:beetroots`.
fn produce_item(host: &dyn Host, block: &str) -> Option<ItemKey> {
    let state = host.block_state_id(block)?;
    host.block_item(state.block())
}

/// Reset a harvested pot: growth and cooldown to 0, in one merge so the chunk is
/// marked changed and comparators hear it (`/data merge block`).
fn reset(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3]) {
    let Some(entity) = host.block_entity(level, pos) else {
        return;
    };
    let mut patch = Compound::new();
    patch.insert(KEY_GROWTH.into(), Tag::Int(0));
    patch.insert(KEY_BONE_MEAL.into(), Tag::Int(0));
    let _ = entity.merge_data(host, patch);
}

// ---------------------------------------------------------------------------
// The `/botanypots info` readout
// ---------------------------------------------------------------------------

/// What `/botanypots info` prints about one pot.
pub(crate) struct Sight {
    pub(crate) block: String,
    pub(crate) growth: u32,
    pub(crate) required: u32,
    pub(crate) soil: Option<String>,
    pub(crate) seed: Option<String>,
    pub(crate) ready: bool,
}

impl Sight {
    /// The report line, exactly the 0.1.0 line the e2e asserts.
    pub(crate) fn line(&self) -> String {
        format!(
            "{}: growth={}/{} soil={} seed={} ready={}",
            self.block,
            self.growth,
            self.required,
            self.soil.as_deref().unwrap_or("none"),
            self.seed.as_deref().unwrap_or("none"),
            self.ready
        )
    }
}

/// The readout for one position: the pot's growth, required ticks, soil, seed and
/// readiness, or `"<block>: not a botany pot"`.
pub(crate) fn info_line(host: &mut dyn ServerHost, pos: [i32; 3]) -> String {
    let level = host.level(host.dimension());
    let block = level
        .and_then(|level| level.block(&*host, pos))
        .map(|block| block.id(&*host))
        .unwrap_or_else(|| "minecraft:air".to_owned());
    let not_a_pot = format!("{block}: not a botany pot");
    if !is_pot(&block) {
        return not_a_pot;
    }
    let Some(level) = level else {
        return not_a_pot;
    };
    let Some(entity) = host.block_entity(level, pos) else {
        return not_a_pot;
    };
    let Some(saved) = entity.data(&*host) else {
        return not_a_pot;
    };
    let saved = read(&saved);
    let soil = entity_slot_key(&*host, &entity, SOIL_SLOT);
    let seed = entity_slot_key(&*host, &entity, SEED_SLOT);
    let reading = reading(&*host, soil, seed, saved.growth);
    Sight {
        block,
        growth: saved.growth,
        required: reading.required,
        soil: saved.soil,
        seed: saved.seed,
        ready: reading.ready,
    }
    .line()
}

/// The command body's argument reader: the block position `/botanypots` names.
pub(crate) fn block_pos(argument: Option<&mod_api::CommandArgumentValue>) -> Option<[i32; 3]> {
    match argument? {
        mod_api::CommandArgumentValue::BlockPos(pos) => Some(*pos),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_pot_declares_two_slots_no_face_reaches_and_its_menu() {
        let container = container();
        assert_eq!(container.slots, SLOT_COUNT, "soil and seed");
        assert_eq!(
            container.faces,
            std::array::from_fn(|_| Vec::<usize>::new()),
            "upstream refuses every hopper face (`canPlaceItemThroughFace` is false)"
        );
        assert!(container.inputs.is_empty() && container.outputs.is_empty());
        assert_eq!(container.menu.as_deref(), Some(MENU));
    }

    #[test]
    fn the_menu_is_upstream_s_two_slot_panel() {
        let screen = menu();
        assert_eq!([screen.width, screen.height], [176.0, 166.0]);
        assert_eq!(
            screen.slots,
            vec![Some([80.0, 48.0]), Some([80.0, 22.0])],
            "BotanyPotMenu's soil and seed slots"
        );
        assert_eq!([screen.inventory_x, screen.inventory_y], [8.0, 84.0]);
        assert!(!screen.own_labels && !screen.own_background);
    }

    #[test]
    fn a_fresh_compound_is_an_empty_pot() {
        assert_eq!(read(&Compound::new()), Saved::default());
    }

    #[test]
    fn the_saved_state_reads_back_from_the_compound_it_wrote() {
        let mut saved = Compound::new();
        let state = Saved {
            growth: 884,
            bone_meal: 17,
            soil: Some("minecraft:dirt".to_owned()),
            seed: Some("minecraft:wheat_seeds".to_owned()),
        };
        write(&mut saved, &state);
        assert_eq!(read(&saved), state);
        assert_eq!(saved.get(&KEY_GROWTH.into()), Some(&Tag::Int(884)));
        assert_eq!(saved.get(&KEY_BONE_MEAL.into()), Some(&Tag::Int(17)));
        assert_eq!(
            saved.get(&KEY_SOIL.into()),
            Some(&Tag::String("minecraft:dirt".into()))
        );
        // An emptied slot saves the empty string, which reads back as `None`.
        let mut emptied = state.clone();
        emptied.soil = None;
        write(&mut saved, &emptied);
        assert_eq!(read(&saved), emptied);
        assert_eq!(
            saved.get(&KEY_SOIL.into()),
            Some(&Tag::String("".into())),
            "the 0.1.0 shape: an empty string, not a removed key"
        );
    }

    #[test]
    fn a_crop_rolls_its_own_block_loot_table() {
        assert_eq!(loot_table_of("minecraft:wheat"), "minecraft:blocks/wheat");
        assert_eq!(
            loot_table_of("minecraft:beetroots"),
            "minecraft:blocks/beetroots"
        );
        assert_eq!(loot_table_of("wheat"), "minecraft:blocks/wheat");
    }

    #[test]
    fn the_info_line_is_the_one_the_e2e_asserts() {
        let empty = Sight {
            block: POT.to_owned(),
            growth: 0,
            required: 0,
            soil: None,
            seed: None,
            ready: false,
        };
        assert_eq!(
            empty.line(),
            "botanypots:terracotta_botany_pot: growth=0/0 soil=none seed=none ready=false"
        );
        let growing = Sight {
            block: POT.to_owned(),
            growth: 52,
            required: 1200,
            soil: Some("minecraft:dirt".to_owned()),
            seed: Some("minecraft:wheat_seeds".to_owned()),
            ready: false,
        };
        assert_eq!(
            growing.line(),
            "botanypots:terracotta_botany_pot: growth=52/1200 soil=minecraft:dirt \
             seed=minecraft:wheat_seeds ready=false"
        );
        let other = Sight {
            block: "minecraft:chest".to_owned(),
            ..growing
        };
        assert!(
            other.line().starts_with("minecraft:chest: growth="),
            "a foreign block still prints its id"
        );
    }
}
