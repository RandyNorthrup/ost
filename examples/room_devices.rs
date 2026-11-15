//! Lists the connected room devices (USB speaker + microphone) and the
//! one Teams' meeting room mode would pick: `room_devices [off]`.
fn main() {
    let on = std::env::args().nth(1).as_deref() != Some("off");
    let r = teams_cli::calling::room_devices::find(on);
    println!("{}", serde_json::to_string_pretty(&r).unwrap());
}
