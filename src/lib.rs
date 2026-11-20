//! Botany Pots for Horizon — the botany pot and the hopper botany pot.
//!
//! One flat SDK package (mod API 0.2): the carried pot content (both blocks'
//! declarations, models, textures, blockstates, lang, loot tables, recipes, tags
//! and the soil tags) is `assets/` and `data/` here, and the behaviour is the one
//! `impl Hooks` below. The rules themselves live in [`runtime`] (the compiled
//! four-crop table, growth, bone meal, yield rolls and the hopper insert rule);
//! [`pot`] is the glue.
//!
//! What the retired bundle expressed as nine injected helpers is here three
//! shapes: the pots' block entity, its tick, the menus and their screen readout
//! are a **Part** (`pot::PotEntity`, attached to the type declared for both
//! blocks), the click route is a second Part on each block key (`pot::PotClick`),
//! the slots are `Registrar` declarations, and the command is the typed
//! `register_commands`/`run_mod_command` pair. Its embedded-content helper has no
//! successor: one `.hmod` carries the content and the code, which is what that
//! helper existed to work around.
use mod_api::{
    self, Command, Flow, Hooks, RegisterCommandsEvent, Registrar, RegistrationContext,
    RunModCommandEvent, ServerHost, Text,
};

mod pot;

pub mod runtime;

#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Declare both pots: the basic pot with two player-only slots, and the
    /// hopper pot with fifteen (soil, seed, an inert tool slot and twelve storage
    /// slots whose bottom face a hopper may take from), each with its own menu,
    /// plus the click Part that harvests a basic pot and fertilises both.
    ///
    /// The retired bundle answered the `block_entity`, `block_entity_ticks`,
    /// `block_entity_container`, `screen` and `right_click_block` hooks with five
    /// separate helpers; a declaration is keyed by the block and the type, so a
    /// foreign block can no longer be answered by mistake. Upstream gives every
    /// pot one block entity type, and the block decides the mode.
    fn register(&self, registrar: &mut dyn Registrar, context: &RegistrationContext) {
        let block = registrar.block_key(pot::POT);
        registrar.block_container(&block, pot::container());
        registrar.block_part(block, pot::PotClick);
        let hopper = registrar.block_key(pot::HOPPER_POT);
        registrar.block_container(&hopper, pot::hopper_container());
        registrar.block_part(hopper, pot::PotClick);
        let kind = pot::declare(registrar);
        if let Err(error) = registrar.block_entity_part(&kind, pot::PotEntity) {
            context.refuse(&error.to_string());
        }
    }

    /// `/botanypots info <x> <y> <z>`: the readout the harness and players use
    /// for a pot's growth, required ticks, soil, seed and readiness.
    fn register_commands(&self, _host: &mut dyn ServerHost, event: &mut RegisterCommandsEvent<'_>) {
        event
            .commands
            .push(Command::new("botanypots info <pos:block_pos>"));
    }

    /// The command body: the position is parsed and resolved by the server's
    /// dispatcher, so this only reads the pot and answers. The line is byte for
    /// byte the 0.1.0 one, so the existing e2e assertions still match.
    fn run_mod_command(
        &self,
        host: &mut dyn ServerHost,
        event: &mut RunModCommandEvent<'_>,
    ) -> Flow {
        let literals: Vec<&str> = event.command.literals.iter().map(String::as_str).collect();
        if literals.first() != Some(&"botanypots") {
            return Flow::Continue;
        }
        let line = match (
            literals.get(1),
            pot::block_pos(event.command.argument("pos")),
        ) {
            (Some(&"info"), Some(pos)) => pot::info_line(host, pos),
            _ => "usage: /botanypots info <x> <y> <z>".to_owned(),
        };
        let _ = host.commands().feedback(Text::literal(line));
        Flow::Cancel
    }
}
