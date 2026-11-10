// Runs at the head of `Game::native_block_entity_tick` (API 15): advance the
// crop's growth while its soil is accepted, and publish the progress.
fn tick(
    game: &mut crate::game::Game<'_>,
    pos: [i32; 3],
    entity: &mut horizon_client::containers::ModBlockEntity,
) {
    crate::game::botanypots_state::on_tick(game, pos, entity);
}
