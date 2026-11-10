// Runs at the head of `Game::native_block_entity_container` (API 16/17): two
// player-only slots (soil, seed) and the two-slot pot menu.
fn observe_container(
    block: &str,
    container: &mut Option<horizon_client::containers::ModContainer>,
) {
    crate::game::botanypots_state::on_container(block, container);
}
