// Runs at the head of `Game::native_screen_draw` (API 19): the growth readout.
fn draw(
    game: &crate::game::Game<'_>,
    block: &str,
    data: &[i32],
    batch: &mut horizon_client::hud::HudBatch,
    origin: [f32; 2],
) {
    crate::game::botanypots_state::on_screen_draw(game, block, data, batch, origin);
}
