// Runs at the head of `Game::native_block_entity_ticks` (API 15): the pots tick.
fn observe_ticks(block: &str, ticks: &mut bool) {
    crate::game::botanypots_state::on_block_entity_ticks(block, ticks);
}
