//! Botany Pots for Horizon — slice 1, the terracotta botany pot.
//!
//! One flat SDK package (mod API 0.2): the carried pot content (block declaration,
//! models, texture, blockstate, lang, loot table, recipe, tags and the jar's
//! crop/soil/interaction/fertilizer data) is `assets/` and `data/` here, and the
//! behaviour is the one `impl Hooks` below. The rules themselves live in
//! [`runtime`], byte-identical to the retired `.hnmod` bundle's `runtime.rs`;
//! [`pot`] is the glue.
//!
//! What the retired bundle expressed as nine injected helpers is here three
//! shapes: the pot's block entity, its tick, its menu and its screen readout are a
//! **Part** (`pot::PotEntity`, attached to the type declared for the block), its
//! click route is a second Part on the block key (`pot::PotClick`), its two slots
//! are a `Registrar` declaration, and the command is the typed
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
    /// Declare the pot: one block with a block entity, two player-only slots and
    /// its menu, and the click Part that harvests and fertilises.
    ///
    /// The retired bundle answered the `block_entity`, `block_entity_ticks`,
    /// `block_entity_container`, `screen` and `right_click_block` hooks with five
    /// separate helpers; a declaration is keyed by the block and the type, so a
    /// foreign block can no longer be answered by mistake.
    fn register(&self, registrar: &mut dyn Registrar, context: &RegistrationContext) {
        let block = registrar.block_key(pot::POT);
        registrar.block_container(&block, pot::container());
        registrar.block_part(block, pot::PotClick);
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
