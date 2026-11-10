// Runs at the head of `Game::native_register_commands` (API 8).
fn register_commands(commands: &mut Vec<NativeCommand>) {
    crate::game::botanypots_state::on_register_commands(commands);
}
