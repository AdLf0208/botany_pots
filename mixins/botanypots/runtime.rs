// The botany pot's pure engine: which crop a seed grows, how much soil and a
// harvest tool shorten the growth, when the pot is ready, what bone meal adds
// and how many times a harvest rolls.
//
// Game-free: the build script's block-entity tick, the interaction hook and
// the command are thin adapters over these functions, and the same file is the
// standalone library's `cargo test` target.
//
// Read from Botany Pots 21.1.44 (`BotanyPotBlockEntity.tickPot`,
// `Helpers.getRequiredGrowthTicks` / `determineRollCount`, `BasicCrop`,
// `BasicSoil`, `BasicFertilizer`). See `../FINDINGS.md`.

/// The suffix every botany pot block id ends with (`botanypots:terracotta_botany_pot`).
const POT_SUFFIX: &str = "_botany_pot";

/// A crop's `grow_time` when its data file does not set one (`BasicCrop.Properties.growTime`).
pub const DEFAULT_GROW_TIME: u32 = 1200;

/// The soil tag `BasicCrop` uses when a crop names none.
pub const DEFAULT_SOIL_TAG: &str = "botanypots:soil/dirt";

/// `minecraft:farmland`'s growth modifier in the jar's own soil data.
pub const FARMLAND_GROWTH_MODIFIER: f32 = 0.10;

/// `bone_meal.json`'s ranged growth (`min`..=`max`).
pub const BONE_MEAL_MIN: u32 = 400;
pub const BONE_MEAL_MAX: u32 = 600;
/// `BasicFertilizer`'s default cooldown, in ticks.
pub const BONE_MEAL_COOLDOWN: u32 = 20;
/// Bone meal never grows a pot past `required - 20`.
pub const BONE_MEAL_MARGIN: u32 = 20;

/// A crop and what a pot does with its seed (`BlockDerivedCrop` + `BasicCrop`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Crop {
    /// The item planted in the seed slot.
    pub seed: &'static str,
    /// The block whose loot table a harvest rolls.
    pub block: &'static str,
    /// The `age` whose state is harvested.
    pub mature_age: u32,
    /// Ticks the crop needs at a growth modifier of 1 (`BasicCrop.growTime`).
    pub grow_time: u32,
    /// The item tag the pot's soil must be in (`BasicCrop.soil`).
    pub soil_tag: &'static str,
    /// `BasicCrop.baseYield`.
    pub base_yield: f32,
    /// `BasicCrop.yieldScale`.
    pub yield_scale: f32,
}

/// The vanilla crops the jar's own `data/botanypots/recipe/minecraft/crop/`
/// files define, with each one's seed and harvest state.
pub const CROPS: [Crop; 4] = [
    Crop {
        seed: "minecraft:wheat_seeds",
        block: "minecraft:wheat",
        mature_age: 7,
        grow_time: DEFAULT_GROW_TIME,
        soil_tag: DEFAULT_SOIL_TAG,
        base_yield: 1.0,
        yield_scale: 1.0,
    },
    Crop {
        seed: "minecraft:carrot",
        block: "minecraft:carrots",
        mature_age: 7,
        grow_time: DEFAULT_GROW_TIME,
        soil_tag: DEFAULT_SOIL_TAG,
        base_yield: 1.0,
        yield_scale: 1.0,
    },
    Crop {
        seed: "minecraft:potato",
        block: "minecraft:potatoes",
        mature_age: 7,
        grow_time: DEFAULT_GROW_TIME,
        soil_tag: DEFAULT_SOIL_TAG,
        base_yield: 1.0,
        yield_scale: 1.0,
    },
    Crop {
        seed: "minecraft:beetroot_seeds",
        block: "minecraft:beetroots",
        mature_age: 3,
        grow_time: DEFAULT_GROW_TIME,
        soil_tag: DEFAULT_SOIL_TAG,
        base_yield: 1.0,
        yield_scale: 1.0,
    },
];

/// Whether `block` is a botany pot of this mod.
#[must_use]
pub fn is_pot(block: &str) -> bool {
    block.starts_with("botanypots:") && block.ends_with(POT_SUFFIX)
}

/// The crop `seed` plants, if this slice knows it.
#[must_use]
pub fn crop_for_seed(seed: &str) -> Option<&'static Crop> {
    CROPS.iter().find(|crop| crop.seed == seed)
}

/// The growth modifier `soil` contributes: `minecraft:farmland` +0.10, every
/// other dirt-family item 0 (`BasicSoil`'s default in the jar's data).
#[must_use]
pub fn soil_growth_modifier(soil: &str) -> f32 {
    if soil == "minecraft:farmland" {
        FARMLAND_GROWTH_MODIFIER
    } else {
        0.0
    }
}

/// Ticks a crop needs with `soil_modifier` added to the global 1.0
/// (`Helpers.getRequiredGrowthTicks`: `floor(cropTime / modifier)`).
#[must_use]
pub fn required_growth_ticks(grow_time: u32, soil_modifier: f32) -> u32 {
    let modifier = 1.0 + soil_modifier.max(0.0);
    let ticks = (f64::from(grow_time) / f64::from(modifier)).floor();
    (ticks.max(1.0) as u32).max(1)
}

/// The pot's growth counter (`BotanyPotBlockEntity.growthTime`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Growth {
    ticks: u32,
}

impl Growth {
    #[must_use]
    pub const fn new() -> Self {
        Self { ticks: 0 }
    }

    /// A counter loaded from a block entity's saved growth.
    #[must_use]
    pub const fn from_ticks(ticks: u32) -> Self {
        let mut growth = Self::new();
        growth.set_ticks(ticks);
        growth
    }

    pub const fn set_ticks(&mut self, ticks: u32) {
        self.ticks = ticks;
    }

    #[must_use]
    pub const fn ticks(&self) -> u32 {
        self.ticks
    }

    pub const fn reset(&mut self) {
        self.ticks = 0;
    }

    /// The pot's tick: one more tick of growth, never past `required` (the
    /// counter is only read through `is_ready`, so clamping changes nothing
    /// and keeps the menu's 16-bit data slot in range).
    ///
    /// Returns whether the pot is ready to harvest.
    pub const fn tick(&mut self, required: u32) -> bool {
        if self.ticks < required {
            self.ticks += 1;
        }
        self.ticks >= required
    }

    #[must_use]
    pub const fn is_ready(&self, required: u32) -> bool {
        self.ticks >= required
    }
}

/// What one bone meal does to `current` growth (`BasicFertilizer.apply`):
/// `min(current + amount, required - BONE_MEAL_MARGIN)`. `None` when the pot
/// cannot be fertilised (`required <= 20`, or already at the cap).
#[must_use]
pub fn bone_meal_step(current: u32, required: u32, amount: u32) -> Option<u32> {
    if required <= BONE_MEAL_MARGIN {
        return None;
    }
    let cap = required - BONE_MEAL_MARGIN;
    if current >= cap {
        return None;
    }
    Some(current.saturating_add(amount).min(cap))
}

/// The total yield of a harvest (`Helpers.getTotalYield`): the crop's base
/// yield plus each modifier scaled by its `yield_scale`.
#[must_use]
pub fn total_yield(crop: &Crop, soil_modifier: f32, tool_modifier: f32) -> f32 {
    crop.base_yield + crop.yield_scale * (soil_modifier + tool_modifier)
}

/// How many times the harvest rolls (`Helpers.determineRollCount`): `floor`
/// guaranteed rolls, plus one when a `roll` in `[0, 1)` beats the remainder.
#[must_use]
pub fn roll_count(chance: f32, roll: f32) -> u32 {
    if !chance.is_finite() || chance <= 0.0 {
        return 0;
    }
    let guaranteed = chance.floor() as u32;
    let remainder = chance - chance.floor();
    guaranteed + u32::from(roll < remainder)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_pot_predicate_accepts_only_botany_pots() {
        assert!(is_pot("botanypots:terracotta_botany_pot"));
        assert!(is_pot("botanypots:white_terracotta_hopper_botany_pot"));
        assert!(!is_pot("botanypots:botany_pot_table"));
        assert!(!is_pot("minecraft:flower_pot"));
        assert!(!is_pot("othermod:terracotta_botany_pot"));
    }

    #[test]
    fn the_four_vanilla_crops_map_their_seed_items() {
        assert_eq!(
            crop_for_seed("minecraft:wheat_seeds").map(|crop| crop.block),
            Some("minecraft:wheat")
        );
        assert_eq!(
            crop_for_seed("minecraft:carrot").map(|crop| crop.block),
            Some("minecraft:carrots")
        );
        assert_eq!(
            crop_for_seed("minecraft:potato").map(|crop| crop.block),
            Some("minecraft:potatoes")
        );
        assert_eq!(
            crop_for_seed("minecraft:beetroot_seeds").map(|crop| crop.mature_age),
            Some(3)
        );
        assert!(crop_for_seed("minecraft:stick").is_none());
    }

    #[test]
    fn farmland_is_the_only_soil_with_a_growth_modifier() {
        assert_eq!(soil_growth_modifier("minecraft:farmland"), 0.10);
        assert_eq!(soil_growth_modifier("minecraft:dirt"), 0.0);
        assert_eq!(soil_growth_modifier("minecraft:sand"), 0.0);
    }

    #[test]
    fn the_required_growth_divides_by_the_modifier() {
        assert_eq!(required_growth_ticks(DEFAULT_GROW_TIME, 0.0), 1200);
        assert_eq!(required_growth_ticks(DEFAULT_GROW_TIME, 0.10), 1090);
        assert_eq!(required_growth_ticks(100, 0.0), 100);
        // A modifier that would make the division zero still costs one tick.
        assert_eq!(required_growth_ticks(0, 0.0), 1);
    }

    #[test]
    fn growth_advances_one_tick_at_a_time_and_stops_at_ready() {
        let mut growth = Growth::new();
        assert_eq!(growth.ticks(), 0);
        assert!(!growth.is_ready(3));
        assert!(!growth.tick(3));
        assert!(!growth.tick(3));
        assert!(growth.tick(3));
        assert_eq!(growth.ticks(), 3);
        // Further ticks do not run the counter past what it needs.
        assert!(growth.tick(3));
        assert_eq!(growth.ticks(), 3);
        growth.reset();
        assert_eq!(growth.ticks(), 0);
    }

    #[test]
    fn bone_meal_adds_a_ranged_amount_and_caps_below_ready() {
        assert_eq!(bone_meal_step(0, 1200, 500), Some(500));
        assert_eq!(bone_meal_step(800, 1200, 500), Some(1180));
        assert_eq!(bone_meal_step(1180, 1200, 500), None);
        assert_eq!(bone_meal_step(0, 20, 500), None);
        assert_eq!(bone_meal_step(0, 21, 500), Some(1));
    }

    #[test]
    fn yield_rolls_are_whole_plus_a_chance() {
        assert_eq!(roll_count(1.0, 0.0), 1);
        assert_eq!(roll_count(1.5, 0.4), 2);
        assert_eq!(roll_count(1.5, 0.6), 1);
        assert_eq!(roll_count(0.5, 0.6), 0);
        assert_eq!(roll_count(0.5, 0.4), 1);
        assert_eq!(roll_count(0.0, 0.0), 0);
    }

    #[test]
    fn total_yield_scales_each_modifier_by_the_crop() {
        let crop = &CROPS[0];
        assert_eq!(total_yield(crop, 0.0, 0.0), 1.0);
        assert_eq!(total_yield(crop, 0.25, 0.25), 1.5);
        let half_scale = Crop {
            yield_scale: 0.5,
            ..*crop
        };
        assert_eq!(total_yield(&half_scale, 0.5, 0.0), 1.25);
    }
}
