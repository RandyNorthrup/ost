//! Sidebar widget: Teams hierarchy with collapsible teams/channels and Chats list.

use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Paragraph, Widget},
};

use crate::api;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A channel inside a team.
#[derive(Clone)]
pub struct Channel {
    pub name: String,
    /// The real channel/thread ID from the API.
    pub id: String,
    /// Messages you haven't read (Teams' isMessageRead false): bold.
    pub unread: bool,
}

/// A team containing channels.
#[derive(Clone)]
#[allow(dead_code)]
pub struct Team {
    pub name: String,
    /// The real team ID from the API.
    pub id: String,
    pub expanded: bool,
    pub channels: Vec<Channel>,
}

/// A direct-message contact.
#[derive(Clone)]
pub struct Chat {
    pub name: String,
    /// The real chat/conversation thread ID from the API.
    pub id: String,
    /// true = group chat (shows a different icon)
    pub is_group: bool,
    /// Unread as Teams counts it (someone else's message newer than your
    /// read horizon, or marked unread): bold, with a dot unless muted.
    pub unread: bool,
    /// You muted it: no dot, and it doesn't count on the Chats header.
    pub muted: bool,
    /// Whether this contact is online (show presence dot)
    pub online: bool,
}

/// Sidebar state: owns the data and tracks navigation.
pub struct SidebarState {
    pub teams: Vec<Team>,
    pub chats: Vec<Chat>,
    /// Index into the flat item list (0-based)
    pub selected: usize,
    /// Whether data is still loading.
    pub loading: bool,
}

impl Default for SidebarState {
    fn default() -> Self {
        Self {
            teams: Vec::new(),
            chats: Vec::new(),
            selected: 0,
            loading: true,
        }
    }
}

impl SidebarState {
    /// Update teams data from API response. A reload keeps the teams you
    /// expanded or collapsed here, the selection on the same row, and
    /// `read` (the conversation you have open) read.
    pub fn update_teams(&mut self, teams: Vec<api::TeamInfo>, read: Option<&str>) {
        let selected = self.selected_key();
        let first_load = self.teams.is_empty();
        let old: std::collections::HashMap<String, bool> =
            self.teams.iter().map(|t| (t.id.clone(), t.expanded)).collect();
        self.teams = teams
            .into_iter()
            .map(|t| Team {
                expanded: if first_load {
                    t.expanded
                } else {
                    old.get(&t.id).copied().unwrap_or(t.expanded)
                },
                name: t.name,
                id: t.id,
                channels: t
                    .channels
                    .into_iter()
                    .map(|c| Channel {
                        unread: c.unread && read != Some(c.id.as_str()),
                        name: c.name,
                        id: c.id,
                    })
                    .collect(),
            })
            .collect();
        self.restore_selection(selected);
    }

    /// Update chats data from API response.
    /// Rename a listed chat (the notes chat once your name is known).
    pub fn rename_chat(&mut self, id: &str, name: String) {
        if let Some(c) = self.chats.iter_mut().find(|c| c.id == id) {
            c.name = name;
        }
    }

    /// Update chats data (Teams' order changes as messages arrive); the
    /// selection stays on the same row and `read` (the open chat) stays
    /// read.
    pub fn update_chats(&mut self, chats: Vec<api::ChatInfo>, read: Option<&str>) {
        let selected = self.selected_key();
        self.chats = chats
            .into_iter()
            .map(|c| Chat {
                unread: c.unread && read != Some(c.id.as_str()),
                muted: c.muted,
                name: c.name,
                id: c.id,
                is_group: c.is_group,
                online: false,
            })
            .collect();
        self.restore_selection(selected);
    }

    /// Set a chat's or channel's unread flag; whether anything changed.
    pub fn set_unread(&mut self, id: &str, unread: bool) -> bool {
        let mut changed = false;
        for c in self.chats.iter_mut().filter(|c| c.id == id) {
            changed |= c.unread != unread;
            c.unread = unread;
        }
        for ch in self.teams.iter_mut().flat_map(|t| t.channels.iter_mut()).filter(|c| c.id == id) {
            changed |= ch.unread != unread;
            ch.unread = unread;
        }
        changed
    }

    /// Whether `id` is one of the listed channels.
    pub fn is_channel(&self, id: &str) -> bool {
        self.teams.iter().flat_map(|t| &t.channels).any(|c| c.id == id)
    }

    /// Unread chats that aren't muted: Teams' Chat badge count.
    pub fn unread_chats(&self) -> usize {
        self.chats.iter().filter(|c| c.unread && !c.muted).count()
    }

    /// What the selection is on, to find it again after a reload.
    fn selected_key(&self) -> Option<(u8, String)> {
        match self.flat_items().get(self.selected)? {
            SidebarItem::Team(ti) => Some((0, self.teams[*ti].id.clone())),
            SidebarItem::Channel(ti, ci) => Some((1, self.teams[*ti].channels[*ci].id.clone())),
            SidebarItem::Chat(ci) => Some((2, self.chats[*ci].id.clone())),
            _ => None,
        }
    }

    /// Put the selection back on the row it was on (it may have moved).
    fn restore_selection(&mut self, key: Option<(u8, String)>) {
        if let Some((kind, id)) = key {
            let items = self.flat_items();
            let found = items.iter().position(|item| match (kind, item) {
                (0, SidebarItem::Team(ti)) => self.teams[*ti].id == id,
                (1, SidebarItem::Channel(ti, ci)) => self.teams[*ti].channels[*ci].id == id,
                (2, SidebarItem::Chat(ci)) => self.chats[*ci].id == id,
                _ => false,
            });
            if let Some(i) = found {
                self.selected = i;
            }
        }
        self.clamp_selection();
    }

    /// Get the chat/channel ID of the currently selected item.
    pub fn selected_item_id(&self) -> Option<String> {
        let items = self.flat_items();
        match items.get(self.selected)? {
            SidebarItem::Channel(ti, ci) => Some(self.teams[*ti].channels[*ci].id.clone()),
            SidebarItem::Chat(ci) => Some(self.chats[*ci].id.clone()),
            _ => None,
        }
    }

    /// Get the display name of the currently selected item.
    pub fn selected_item_name(&self) -> Option<String> {
        let items = self.flat_items();
        match items.get(self.selected)? {
            SidebarItem::Channel(ti, ci) => {
                let team = &self.teams[*ti];
                let channel = &team.channels[*ci];
                Some(format!("{} > #{}", team.name, channel.name))
            }
            SidebarItem::Chat(ci) => Some(self.chats[*ci].name.clone()),
            SidebarItem::Team(ti) => Some(self.teams[*ti].name.clone()),
            _ => None,
        }
    }
}

// ---------------------------------------------------------------------------
// Flat item enumeration
// ---------------------------------------------------------------------------

/// One row in the sidebar's flat list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SidebarItem {
    /// "TEAMS" section header (not selectable, but occupies a row)
    TeamsHeader,
    /// A team row (index into SidebarState.teams)
    Team(usize),
    /// A channel row (team_idx, channel_idx)
    Channel(usize, usize),
    /// "CHATS" separator
    ChatsHeader,
    /// A chat row (index into SidebarState.chats)
    Chat(usize),
}

impl SidebarState {
    /// Build a flat list of items in display order.
    pub fn flat_items(&self) -> Vec<SidebarItem> {
        let mut items = Vec::new();

        // Teams header
        items.push(SidebarItem::TeamsHeader);

        for (ti, team) in self.teams.iter().enumerate() {
            items.push(SidebarItem::Team(ti));
            if team.expanded {
                for (ci, _ch) in team.channels.iter().enumerate() {
                    items.push(SidebarItem::Channel(ti, ci));
                }
            }
        }

        // Chats separator
        items.push(SidebarItem::ChatsHeader);

        for (ci, _chat) in self.chats.iter().enumerate() {
            items.push(SidebarItem::Chat(ci));
        }

        items
    }

    /// Total number of flat items.
    pub fn item_count(&self) -> usize {
        self.flat_items().len()
    }

    /// Move selection up.
    pub fn move_up(&mut self) {
        if self.selected > 0 {
            self.selected -= 1;
            self.skip_headers_up();
        }
    }

    /// Move selection down.
    pub fn move_down(&mut self) {
        let count = self.item_count();
        if count == 0 {
            return;
        }
        if self.selected < count - 1 {
            self.selected += 1;
            self.skip_headers_down();
        }
    }

    /// Toggle expand/collapse if current selection is a Team row.
    pub fn toggle_expand(&mut self) {
        let items = self.flat_items();
        if let Some(SidebarItem::Team(ti)) = items.get(self.selected) {
            self.teams[*ti].expanded = !self.teams[*ti].expanded;
        }
    }

    /// Skip non-selectable headers when moving up.
    fn skip_headers_up(&mut self) {
        let items = self.flat_items();
        while self.selected > 0 {
            match items.get(self.selected) {
                Some(SidebarItem::TeamsHeader | SidebarItem::ChatsHeader) => {
                    self.selected -= 1;
                }
                _ => break,
            }
        }
        // If we landed on TeamsHeader (index 0), move down instead
        if let Some(SidebarItem::TeamsHeader | SidebarItem::ChatsHeader) = items.get(self.selected)
        {
            self.skip_headers_down();
        }
    }

    /// Skip non-selectable headers when moving down.
    fn skip_headers_down(&mut self) {
        let items = self.flat_items();
        let count = items.len();
        while self.selected < count - 1 {
            match items.get(self.selected) {
                Some(SidebarItem::TeamsHeader | SidebarItem::ChatsHeader) => {
                    self.selected += 1;
                }
                _ => break,
            }
        }
    }

    /// Clamp selected index to valid range after structural changes.
    pub fn clamp_selection(&mut self) {
        let count = self.item_count();
        if count == 0 {
            self.selected = 0;
            return;
        }
        if self.selected >= count {
            self.selected = count - 1;
        }
        // After clamping, skip headers
        self.skip_headers_down();
    }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Render the sidebar into the given area.
pub fn render(area: Rect, buf: &mut Buffer, state: &SidebarState, focused: bool) {
    let border_style = if focused {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    let border_type = if focused {
        BorderType::Double
    } else {
        BorderType::Plain
    };

    let block = Block::default()
        .borders(Borders::ALL)
        .border_type(border_type)
        .border_style(border_style);

    let inner = block.inner(area);
    block.render(area, buf);

    // Show loading indicator if data hasn't arrived yet.
    if state.loading && state.teams.is_empty() && state.chats.is_empty() {
        if inner.height > 0 && inner.width > 0 {
            let loading_area = Rect::new(inner.x, inner.y, inner.width, 1);
            let line = Line::from(Span::styled(
                " Loading...",
                Style::default().fg(Color::DarkGray),
            ));
            Paragraph::new(line).render(loading_area, buf);
        }
        return;
    }

    let items = state.flat_items();
    let available_height = inner.height as usize;

    if available_height == 0 || items.is_empty() {
        return;
    }

    // Compute scroll offset so selected item is visible.
    let scroll_offset = compute_scroll_offset(state.selected, available_height, items.len());

    for (row_idx, item_idx) in (scroll_offset..items.len())
        .take(available_height)
        .enumerate()
    {
        let item = &items[item_idx];
        let ctx = RowCtx {
            area: Rect::new(inner.x, inner.y + row_idx as u16, inner.width, 1),
            selected: item_idx == state.selected,
            pane_focused: focused,
        };

        render_item(buf, &ctx, item, state);
    }
}

/// Simple scroll offset: keep selected item visible.
fn compute_scroll_offset(selected: usize, height: usize, total: usize) -> usize {
    if total <= height {
        return 0;
    }
    if selected < height {
        return 0;
    }
    let max_offset = total.saturating_sub(height);
    let offset = selected.saturating_sub(height - 1);
    offset.min(max_offset)
}

/// Rendering context for a single sidebar row.
struct RowCtx {
    area: Rect,
    selected: bool,
    pane_focused: bool,
}

/// Style for a list item (channel or chat) based on selection and unread state.
fn item_style(selected: bool, has_unread: bool) -> Style {
    if selected {
        Style::default()
            .fg(Color::White)
            .bg(Color::DarkGray)
            .add_modifier(Modifier::BOLD)
    } else if has_unread {
        Style::default()
            .fg(Color::White)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::Gray)
    }
}

/// Style for a badge (unread count) based on selection state.
fn badge_style(selected: bool) -> Style {
    if selected {
        Style::default()
            .fg(Color::Yellow)
            .bg(Color::DarkGray)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default()
            .fg(Color::Yellow)
            .add_modifier(Modifier::BOLD)
    }
}

/// Render a single sidebar item into the buffer.
fn render_item(buf: &mut Buffer, ctx: &RowCtx, item: &SidebarItem, state: &SidebarState) {
    let w = ctx.area.width as usize;
    match item {
        SidebarItem::TeamsHeader => {
            let label = if ctx.pane_focused {
                ">> TEAMS"
            } else {
                "   TEAMS"
            };
            let style = Style::default()
                .fg(Color::White)
                .add_modifier(Modifier::BOLD);
            render_row(buf, ctx.area, label, "", style, style);
        }

        SidebarItem::Team(ti) => {
            let team = &state.teams[*ti];
            let indicator = if team.expanded {
                "\u{25BC}"
            } else {
                "\u{25B6}"
            };
            let cursor = if ctx.selected { "\u{25BA}" } else { " " };
            let label = format!("{}{} {}", cursor, indicator, team.name);

            // Teams bolds a team only while it is collapsed and one of its
            // channels is unread.
            let unread = !team.expanded && team.channels.iter().any(|c| c.unread);
            let style = if ctx.selected {
                Style::default()
                    .fg(Color::White)
                    .bg(Color::DarkGray)
                    .add_modifier(Modifier::BOLD)
            } else if unread {
                Style::default().fg(Color::White).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };

            render_row(buf, ctx.area, &label, "", style, style);
        }

        SidebarItem::Channel(ti, ci) => {
            let channel = &state.teams[*ti].channels[*ci];
            let cursor = if ctx.selected { "\u{25BA}" } else { " " };
            let label = format!("  {}# {}", cursor, channel.name);
            // Teams shows an unread channel in bold (no count).
            let style = item_style(ctx.selected, channel.unread);
            render_row(buf, ctx.area, &label, "", style, style);
        }

        SidebarItem::ChatsHeader => {
            // Render a separator line: " -- CHATS --------", with Teams'
            // Chat badge (unread chats that aren't muted).
            let unread = state.unread_chats();
            let prefix = if unread > 0 {
                format!(" -- CHATS ({unread}) ")
            } else {
                " -- CHATS ".to_string()
            };
            let prefix = prefix.as_str();
            let dashes = w.saturating_sub(prefix.len());
            let label = format!("{}{}", prefix, "-".repeat(dashes));
            let style = Style::default().fg(Color::DarkGray);
            render_row(buf, ctx.area, &label, "", style, style);
        }

        SidebarItem::Chat(ci) => {
            let chat = &state.chats[*ci];
            let icon = if chat.is_group {
                "\u{1F465}"
            } else {
                "\u{1F464}"
            };
            let cursor = if ctx.selected { "\u{25BA}" } else { " " };
            let label = format!("{}{} {}", cursor, icon, chat.name);
            // Teams: an unread chat is bold, with a dot unless it's muted.
            let dot = chat.unread && !chat.muted;
            let badge = if dot {
                "\u{25CF}".to_string()
            } else if chat.online {
                "*".to_string()
            } else {
                String::new()
            };

            let style = item_style(ctx.selected, chat.unread);
            let bstyle = if dot {
                badge_style(ctx.selected)
            } else if chat.online {
                Style::default().fg(Color::Green)
            } else {
                style
            };

            render_row(buf, ctx.area, &label, &badge, style, bstyle);
        }
    }
}

/// Render a row with left-aligned text and an optional right-aligned badge.
fn render_row(
    buf: &mut Buffer,
    area: Rect,
    left: &str,
    badge: &str,
    text_style: Style,
    badge_style: Style,
) {
    let width = area.width as usize;
    if width == 0 {
        return;
    }

    // Truncate left text if needed, leaving room for badge + 1 space
    let badge_w = unicode_width::UnicodeWidthStr::width(badge);
    let max_left = if badge_w > 0 {
        width.saturating_sub(badge_w + 1)
    } else {
        width
    };

    // Truncate by display width, not char count
    let mut left_truncated = String::new();
    let mut left_w = 0;
    for ch in left.chars() {
        let cw = unicode_width::UnicodeWidthChar::width(ch).unwrap_or(0);
        if left_w + cw > max_left {
            break;
        }
        left_truncated.push(ch);
        left_w += cw;
    }

    // Padding between left text and badge
    let pad = if badge_w > 0 {
        width.saturating_sub(left_w + badge_w)
    } else {
        width.saturating_sub(left_w)
    };

    // Build the line
    let line = Line::from(vec![
        Span::styled(left_truncated, text_style),
        Span::styled(" ".repeat(pad), text_style),
        Span::styled(badge.to_string(), badge_style),
    ]);

    let row_area = Rect::new(area.x, area.y, area.width, 1);
    Paragraph::new(line).render(row_area, buf);
}
