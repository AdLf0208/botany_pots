// Runs at the head of `Game::native_screen` (API 19): the pot's two-slot layout.
fn observe_screen(block: &str, screen: &mut Option<NativeScreen>) {
    crate::game::botanypots_state::on_screen(block, screen);
}
