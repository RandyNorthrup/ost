//! Help popup overlay: shows all keyboard shortcuts organized by category.

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
};

/// Popup dimensions.
const POPUP_WIDTH: u16 = 84;
const POPUP_HEIGHT: u16 = 30;

/// A shortcut entry: key binding and its description.
struct Shortcut {
    key: &'static str,
    desc: &'static str,
}

/// A category of shortcuts with a title.
struct Category {
    title: &'static str,
    shortcuts: &'static [Shortcut],
}

// Only keys the TUI handles (src/tui/app.rs), by where they work.
const NAVIGATION: Category = Category {
    title: "NAVIGATION",
    shortcuts: &[
        Shortcut {
            key: "Up/Down j/k",
            desc: "Move up and down",
        },
        Shortcut {
            key: "Left/Right",
            desc: "Switch between panes",
        },
        Shortcut {
            key: "Tab",
            desc: "Cycle focus forward",
        },
        Shortcut {
            key: "Shift+Tab",
            desc: "Cycle focus backward",
        },
        Shortcut {
            key: "Enter",
            desc: "Open chat / expand team",
        },
        Shortcut {
            key: "Enter",
            desc: "Show or hide a thread",
        },
    ],
};

const PANES: Category = Category {
    title: "PANES",
    shortcuts: &[
        Shortcut {
            key: "1",
            desc: "Teams and chats",
        },
        Shortcut {
            key: "2",
            desc: "Messages",
        },
        Shortcut {
            key: "3",
            desc: "Compose",
        },
    ],
};

const VIEWS: Category = Category {
    title: "ANYWHERE",
    shortcuts: &[
        Shortcut {
            key: "Ctrl+K",
            desc: "Search",
        },
        Shortcut {
            key: "Ctrl+D",
            desc: "Show or hide debug log",
        },
        Shortcut {
            key: "PgUp/PgDn",
            desc: "Scroll the debug log",
        },
        Shortcut {
            key: "?",
            desc: "Show or hide this help",
        },
        Shortcut {
            key: "q",
            desc: "Quit (outside compose)",
        },
    ],
};

const MESSAGING: Category = Category {
    title: "COMPOSE",
    shortcuts: &[
        Shortcut {
            key: "Enter",
            desc: "Send",
        },
        Shortcut {
            key: "Ctrl+Enter",
            desc: "New line",
        },
        Shortcut {
            key: "Ctrl+U",
            desc: "Clear the box",
        },
        Shortcut {
            key: "Left/Right",
            desc: "Move the cursor",
        },
        Shortcut {
            key: "Home/End",
            desc: "Start / end of the text",
        },
        Shortcut {
            key: "Bksp/Del",
            desc: "Delete a character",
        },
        Shortcut {
            key: "Esc",
            desc: "Back to messages",
        },
    ],
};

const ACTIONS: Category = Category {
    title: "SEARCH (Ctrl+K)",
    shortcuts: &[
        Shortcut {
            key: "Up/Down",
            desc: "Choose a result",
        },
        Shortcut {
            key: "Enter",
            desc: "Open it",
        },
        Shortcut {
            key: "Esc",
            desc: "Close search",
        },
    ],
};

const MISC: Category = Category {
    title: "HELP",
    shortcuts: &[
        Shortcut {
            key: "Any key",
            desc: "Close this help",
        },
    ],
};

/// Render the help overlay over `area` (everything between the header and
/// the status bar).
///
/// The whole area is cleared first, so no message or sidebar text shows
/// around the popup, then a bordered box with all keyboard shortcuts is
/// drawn centered in it, in a two-column layout.
pub fn render_help_popup(frame: &mut Frame, area: Rect) {
    // Calculate centered popup area, clamped to the area.
    let popup_w = POPUP_WIDTH.min(area.width.saturating_sub(2));
    let popup_h = POPUP_HEIGHT.min(area.height.saturating_sub(2));

    let popup_area = centered_rect(popup_w, popup_h, area);

    // Clear everything behind and around the popup.
    frame.render_widget(Clear, area);

    // Outer block with title and footer.
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan))
        .title(Line::from(vec![
            Span::styled(
                " HELP ",
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled("(? to close) ", Style::default().fg(Color::Gray)),
        ]))
        .title_bottom(Line::from(Span::styled(
            " Press any key to close ",
            Style::default().fg(Color::Gray),
        )));

    let inner = block.inner(popup_area);
    frame.render_widget(block, popup_area);

    if inner.height == 0 || inner.width == 0 {
        return;
    }

    // Split inner area into two columns.
    let [left_col, right_col] =
        Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(inner);

    // Left column: Navigation, Panes, Views
    let left_lines = build_column_lines(&[&NAVIGATION, &PANES, &VIEWS]);
    let left_para = Paragraph::new(left_lines);
    frame.render_widget(left_para, inset(left_col, 1, 1));

    // Right column: Messaging, Actions, Misc
    let right_lines = build_column_lines(&[&MESSAGING, &ACTIONS, &MISC]);
    let right_para = Paragraph::new(right_lines);
    frame.render_widget(right_para, inset(right_col, 1, 1));
}

/// Build the lines for one column of categories.
fn build_column_lines<'a>(categories: &[&Category]) -> Vec<Line<'a>> {
    let mut lines: Vec<Line<'a>> = Vec::new();

    for (cat_idx, cat) in categories.iter().enumerate() {
        if cat_idx > 0 {
            // Blank line between categories.
            lines.push(Line::from(""));
        }

        // Category title.
        lines.push(Line::from(Span::styled(
            cat.title,
            Style::default()
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        )));

        // Separator line under title.
        let sep_len = 36;
        let sep: String = "\u{2500}".repeat(sep_len);
        lines.push(Line::from(Span::styled(
            sep,
            Style::default().fg(Color::DarkGray),
        )));

        // Shortcut entries.
        for sc in cat.shortcuts.iter() {
            let key_width = 12;
            let key_display = format!("{:<width$}", sc.key, width = key_width);
            lines.push(Line::from(vec![
                Span::styled(key_display, Style::default().fg(Color::Yellow)),
                Span::styled(sc.desc, Style::default().fg(Color::Gray)),
            ]));
        }
    }

    lines
}

/// Return a centered sub-rect of the given size within `area`.
fn centered_rect(width: u16, height: u16, area: Rect) -> Rect {
    let x = area.x + area.width.saturating_sub(width) / 2;
    let y = area.y + area.height.saturating_sub(height) / 2;
    Rect::new(x, y, width, height)
}

/// Inset a rect by the given horizontal and vertical margins.
fn inset(area: Rect, h: u16, v: u16) -> Rect {
    Rect::new(
        area.x + h,
        area.y + v,
        area.width.saturating_sub(h * 2),
        area.height.saturating_sub(v * 2),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_help_overlay_hides_everything_around_it() {
        use ratatui::{Terminal, backend::TestBackend, widgets::Paragraph};
        let mut term = Terminal::new(TestBackend::new(160, 45)).unwrap();
        term.draw(|f| {
            let area = f.area();
            // Message text everywhere, then the overlay over the middle rows.
            let filler = (0..area.height).map(|_| "█".repeat(area.width as usize)).collect::<Vec<_>>().join("\n");
            f.render_widget(Paragraph::new(filler), area);
            render_help_popup(f, Rect::new(0, 1, area.width, area.height - 2));
        })
        .unwrap();
        let buf = term.backend().buffer();
        for y in 1..44 {
            for x in 0..160 {
                assert_ne!(buf[(x, y)].symbol(), "█", "text shows through at {x},{y}");
            }
        }
        // The header and status rows are left alone.
        assert_eq!(buf[(0, 0)].symbol(), "█");
        assert_eq!(buf[(0, 44)].symbol(), "█");
    }

    #[test]
    fn the_help_lists_only_handled_keys() {
        let all: Vec<&str> = [&NAVIGATION, &PANES, &VIEWS, &MESSAGING, &ACTIONS, &MISC]
            .iter()
            .flat_map(|c| c.shortcuts.iter().map(|s| s.key))
            .collect();
        // Keys the TUI doesn't handle (src/tui/app.rs).
        for gone in ["g g", "G", "/", "r", "e", "d", "+", "@", "Ctrl+P", "Ctrl+R", "Ctrl+N", "Ctrl+T", "Ctrl+,", "F1", "F2", "F3", "F4", "F5"] {
            assert!(!all.contains(&gone), "{gone} is listed but not handled");
        }
        for kept in ["Ctrl+K", "Ctrl+D", "Ctrl+U", "Ctrl+Enter", "Enter", "q", "?", "1", "2", "3"] {
            assert!(all.contains(&kept), "{kept} is handled but not listed");
        }
    }
}
