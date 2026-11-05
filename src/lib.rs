//! OST engine: Teams protocol, auth, messaging, calling and media.
//!
//! The `teams-cli` binary and the desktop app are both thin front ends over
//! this library, so protocol fixes land in one place.

pub mod api;
pub mod auth;
pub mod calling;
pub mod config;
pub mod event_hub;
pub mod models;
pub mod trouter;
pub mod tui;
