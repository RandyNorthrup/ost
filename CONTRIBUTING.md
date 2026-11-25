# Contributing to OST

Thanks for helping. OST is a native Linux client for Microsoft Teams: the
desktop app (`ost-desktop`, Rust and Qt Quick through CXX-Qt in `desktop/`),
the terminal client (`teams-cli`) and the engine they share (`src/`), plus the
video effects crate (`vfx/`). By taking part you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Where to ask

- Questions: [Q&A](https://github.com/RandyNorthrup/ost/discussions/categories/q-a) in Discussions.
- Ideas: [Ideas](https://github.com/RandyNorthrup/ost/discussions/categories/ideas).
- Bugs: [open an issue](https://github.com/RandyNorthrup/ost/issues/new?template=report-a-problem.yml),
  or Settings and more ▸ Feedback ▸ Report a problem in OST.
- Security problems: privately, as [SECURITY.md](SECURITY.md) describes,
  never in a public issue.

For a larger change, open an issue or discussion first so the approach can
be agreed before you write it.

## Build

The dependencies and commands are in the README's
[Build from source](README.md#build-from-source) and in
[docs/desktop.md](docs/desktop.md#build): Rust stable (edition 2024), Qt 6.9
or newer, FFmpeg, PipeWire, ALSA, OpenSSL, webrtc-audio-processing, clang,
CMake and NASM. CI builds on Ubuntu 26.04 with the packages listed in
[desktop/packaging/debian/control](desktop/packaging/debian/control)
(`sudo sh desktop/packaging/build-deb.sh --deps-only` installs them there).

```bash
cargo build -p ost-desktop                  # the desktop app
cargo build --bin teams-cli --features audio  # the terminal client, with call audio
```

The C++ parts are heavy; on machines with little memory use `-j 2`.

## Test

```bash
cargo test --features audio,video --lib   # engine
cargo test -p ost-desktop                 # desktop backend
cargo test -p ost-vfx                     # video effects
```

`just e2e` runs the terminal client's end-to-end tests, and the desktop app
drives itself with test flags
([docs/desktop.md](docs/desktop.md#test-harness)). Both work on the
signed-in account and send real messages, so use a test account, never your
work account or other people's chats.

## Code style

- `cargo fmt --all` (rustfmt defaults) and
  `cargo clippy --workspace --all-targets -- -D warnings` must be clean; CI
  checks both. `just check` runs them locally.
- Keep changes focused, and follow the patterns of the code around them.
  Comments say why, not what.
- Don't commit secrets, tokens, logs with personal data, Microsoft's
  translated strings (OST downloads them at run time) or large binaries such
  as models (download them on first use with a pinned SHA-256).
- After changing dependencies, regenerate the third-party notices with
  `just notices`.

## How features are matched to Teams

OST aims to look and work like the Teams desktop app, natively, with only
the name and logo different. Features aren't designed from screenshots:

1. Find out exactly what Teams does: its behavior in the live Windows app
   and its own code and service calls. The results are written up in
   [docs/spec](docs/spec), which is authoritative. The inventories in
   [docs/parity](docs/parity) list what exists, from Microsoft's documentation.
2. Build it with the same services and protocols Teams uses
   ([docs/architecture.md](docs/architecture.md)), as native Qt Quick, not
   web views. Microsoft's own embedded web apps (Whiteboard, Loop and so on)
   are hosted as Teams hosts them.
3. Check the result side by side with Teams on a test account.

If something deliberately works differently from Teams, say so in the pull
request and in [docs/desktop.md](docs/desktop.md).

## Backlog

Work is tracked as tasks in [backlog/tasks](backlog/tasks), managed with
the [Backlog.md](https://github.com/MrLesk/Backlog.md) CLI
(`backlog task list --plain`, `backlog task 42 --plain`). Each task has a
description and acceptance criteria; add or update tasks with the CLI, not by
editing the files. Reference the task (for example `TASK-0285`) in your
commits and pull request.

## Pull requests

- Base them on `main`. CI (format, clippy, build and tests) must pass before
  merging.
- Describe what changed, why, and how you tested it; include screenshots for
  UI changes.
- Contributions are licensed under the project's [MIT License](LICENSE).
