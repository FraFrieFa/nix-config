use crate::app::{App, ConfigSource, NetworkStatus, Screen};
use crate::disk::format_bytes;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    widgets::{Block, BorderType, Borders, List, ListItem, ListState, Paragraph, Wrap},
    Frame,
};

// ── Colour palette ───────────────────────────────────────────────────────────
const INDIGO: Color = Color::Rgb(99, 102, 241); // border / accent
const INDIGO_LT: Color = Color::Rgb(165, 180, 252); // title text
const INDIGO_HL: Color = Color::Rgb(67, 56, 202); // selection bg
const SLATE: Color = Color::Rgb(100, 116, 139); // dim / help text
const GREEN: Color = Color::Rgb(34, 197, 94); // success
const RED: Color = Color::Rgb(239, 68, 68); // error
const AMBER: Color = Color::Rgb(251, 191, 36); // warning / spinner

fn block(title: &str) -> Block<'_> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(INDIGO))
        .title(format!(" {} ", title))
        .title_style(Style::default().fg(INDIGO_LT).add_modifier(Modifier::BOLD))
}

fn highlight_style() -> Style {
    Style::default()
        .bg(INDIGO_HL)
        .fg(Color::White)
        .add_modifier(Modifier::BOLD)
}

// ── Top-level render ─────────────────────────────────────────────────────────
pub fn render(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(0),
            Constraint::Length(1),
        ])
        .split(f.area());

    let title = Paragraph::new("✦  NixOS Installer  ✦")
        .style(Style::default().fg(INDIGO_LT).add_modifier(Modifier::BOLD))
        .alignment(Alignment::Center)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(INDIGO)),
        );
    f.render_widget(title, chunks[0]);

    let help_bar = Paragraph::new(help_text(app)).style(Style::default().fg(SLATE));
    f.render_widget(help_bar, chunks[2]);

    render_screen(f, app, chunks[1]);
}

fn help_text(app: &App) -> &'static str {
    match &app.screen {
        Screen::ConfigSource { .. }
        | Screen::HostSelect { .. }
        | Screen::DiskSelect { .. }
        | Screen::FreeSpaceSelect { .. }
        | Screen::OverprovisionChoice { .. } => {
            " ↑↓ / jk  navigate    Enter  select    Esc  back    Ctrl-C  quit"
        }
        Screen::LoadingHosts => " Esc  cancel    Ctrl-C  quit",
        Screen::Passphrase { .. } | Screen::SetPasswords { .. } => {
            " Tab  switch field    Enter  confirm    Esc  back    Ctrl-C  quit"
        }
        Screen::Summary => " Enter / y  begin install    Esc  back    Ctrl-C  quit",
        Screen::Installing { .. } => {
            " ↑↓ / jk  scroll    q / Enter  quit when done    Ctrl-C  quit"
        }
        Screen::Done | Screen::Error(_) => " Any key  exit    Ctrl-C  quit",
    }
}

// ── Screen dispatch ──────────────────────────────────────────────────────────
fn render_screen(f: &mut Frame, app: &App, area: Rect) {
    match &app.screen {
        Screen::ConfigSource { selected, network } => {
            render_config_source(f, area, *selected, network, app.tick);
        }

        Screen::LoadingHosts => {
            let spinner_chars = ['|', '/', '-', '\\'];
            let spinner = spinner_chars[app.tick % spinner_chars.len()];
            let p = Paragraph::new(format!("\n\n  {} Reading NixOS configurations...", spinner))
                .style(Style::default().fg(AMBER).add_modifier(Modifier::BOLD))
                .block(block("Loading"));
            f.render_widget(p, area);
        }

        Screen::HostSelect { hosts, selected } => {
            let items: Vec<ListItem> = hosts
                .iter()
                .map(|h| ListItem::new(format!("  {}", h)))
                .collect();
            render_list(f, area, "Select Host", items, *selected);
        }

        Screen::DiskSelect { disks, selected } => {
            let items: Vec<ListItem> = disks
                .iter()
                .map(|d| {
                    ListItem::new(format!(
                        "  {:12}  {:>10}  {}",
                        d.name,
                        format_bytes(d.size_bytes),
                        d.model
                    ))
                })
                .collect();
            render_list(f, area, "Select Disk", items, *selected);
        }

        Screen::FreeSpaceSelect { extents, selected } => {
            let items: Vec<ListItem> = extents
                .iter()
                .enumerate()
                .map(|(i, e)| {
                    ListItem::new(format!(
                        "  Region {}   {:>10}   LBA {}-{}",
                        i + 1,
                        format_bytes(e.size_bytes),
                        e.start_lba,
                        e.end_lba,
                    ))
                })
                .collect();
            render_list(
                f,
                area,
                "Select Empty Space for Boot + Root",
                items,
                *selected,
            );
        }

        Screen::Passphrase {
            input,
            confirm,
            focused,
            mismatch,
        } => {
            render_passphrase(
                f,
                area,
                "Encryption Passphrase",
                input,
                confirm,
                *focused,
                *mismatch,
            );
        }

        Screen::OverprovisionChoice { selected, is_ssd } => {
            let tag = if *is_ssd {
                " — SSD detected"
            } else {
                " — HDD"
            };
            let title = format!("Overprovisioning{}", tag);
            let items = vec![
                ListItem::new("  0%"),
                ListItem::new("  7%"),
                ListItem::new("  10%"),
                ListItem::new("  20%"),
            ];
            render_list(f, area, &title, items, *selected);
        }

        Screen::Summary => render_summary(f, area, app),

        Screen::Installing { log, scroll } => {
            render_installing(f, area, log, *scroll, app.install_done, app.install_error);
        }

        Screen::SetPasswords {
            users,
            collected,
            input,
            confirm,
            focused,
            mismatch,
        } => {
            let idx = collected.len();
            let user = &users[idx.min(users.len() - 1)];
            let title = format!("Set Password — {} ({}/{})", user, idx + 1, users.len());
            render_passphrase(f, area, &title, input, confirm, *focused, *mismatch);
        }

        Screen::Done => {
            let p = Paragraph::new("\n\n  Installation complete!\n\n  Press any key to exit.")
                .style(Style::default().fg(GREEN).add_modifier(Modifier::BOLD))
                .alignment(Alignment::Left)
                .block(block("Done"));
            f.render_widget(p, area);
        }

        Screen::Error(msg) => {
            let text = format!("\n  {}\n\n  Press any key to exit.", msg);
            let p = Paragraph::new(text)
                .style(Style::default().fg(RED))
                .wrap(Wrap { trim: false })
                .block(
                    Block::default()
                        .borders(Borders::ALL)
                        .border_type(BorderType::Rounded)
                        .border_style(Style::default().fg(RED))
                        .title(" Error ")
                        .title_style(Style::default().fg(RED).add_modifier(Modifier::BOLD)),
                );
            f.render_widget(p, area);
        }
    }
}

// ── Shared widgets ───────────────────────────────────────────────────────────
fn render_list(f: &mut Frame, area: Rect, title: &str, items: Vec<ListItem>, selected: usize) {
    let list = List::new(items)
        .block(block(title))
        .highlight_style(highlight_style())
        .highlight_symbol("▶ ");
    let mut state = ListState::default();
    state.select(Some(selected));
    f.render_stateful_widget(list, area, &mut state);
}

fn render_config_source(
    f: &mut Frame,
    area: Rect,
    selected: usize,
    network: &NetworkStatus,
    tick: usize,
) {
    let pull_style = if !network.checking && network.online && network.git_available {
        Style::default()
    } else {
        Style::default().fg(SLATE)
    };
    let items = vec![
        ListItem::new("  Pull latest config from GitHub").style(pull_style),
        ListItem::new("  Use embedded config (offline)"),
    ];

    let outer = block("Config Source");
    let inner = outer.inner(area);
    f.render_widget(outer, area);

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0)])
        .split(inner);

    let spinner_chars = ['|', '/', '-', '\\'];
    let spinner = spinner_chars[tick % spinner_chars.len()];
    let prefix = if network.checking {
        format!("{} ", spinner)
    } else if network.online && network.git_available {
        "OK ".to_string()
    } else {
        "!! ".to_string()
    };

    let status_color = if network.checking {
        AMBER
    } else if network.online && network.git_available {
        GREEN
    } else {
        AMBER
    };
    let p = Paragraph::new(format!("  {}{}", prefix, network.message))
        .style(Style::default().fg(status_color));
    f.render_widget(p, chunks[0]);

    let list = List::new(items)
        .highlight_style(highlight_style())
        .highlight_symbol("▶ ");
    let mut state = ListState::default();
    state.select(Some(selected));
    f.render_stateful_widget(list, chunks[1], &mut state);
}

fn render_passphrase(
    f: &mut Frame,
    area: Rect,
    title: &str,
    input: &str,
    confirm: &str,
    focused: usize,
    mismatch: bool,
) {
    let outer = block(title);
    f.render_widget(outer, area);

    let inner = Rect {
        x: area.x + 1,
        y: area.y + 1,
        width: area.width.saturating_sub(2),
        height: area.height.saturating_sub(2),
    };

    let row_count = if mismatch { 3 } else { 2 };
    let constraints: Vec<Constraint> = (0..row_count).map(|_| Constraint::Length(3)).collect();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints(constraints)
        .split(inner);

    let field_style = |idx: usize| {
        if focused == idx {
            Style::default().fg(INDIGO_LT)
        } else {
            Style::default().fg(SLATE)
        }
    };

    let field_block = |label: &'static str, idx: usize| {
        Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(field_style(idx))
            .title(format!(" {} ", label))
            .title_style(field_style(idx))
    };

    let p0 = Paragraph::new("*".repeat(input.len())).block(field_block("Passphrase", 0));
    f.render_widget(p0, chunks[0]);

    let p1 = Paragraph::new("*".repeat(confirm.len())).block(field_block("Confirm", 1));
    f.render_widget(p1, chunks[1]);

    if mismatch && chunks.len() > 2 {
        let warn = Paragraph::new("  ✗  Passphrases do not match")
            .style(Style::default().fg(RED).add_modifier(Modifier::BOLD));
        f.render_widget(warn, chunks[2]);
    }
}

fn render_summary(f: &mut Frame, area: Rect, app: &App) {
    let cfg = &app.config;
    let source = match &cfg.config_source {
        ConfigSource::EmbeddedOffline => "embedded config (offline)",
        ConfigSource::PulledFromGit => "latest config from GitHub",
    };

    let mut lines = vec![
        format!("  Host    {}", cfg.host),
        format!(
            "  Disk    /dev/{}  ({})",
            cfg.disk.name,
            format_bytes(cfg.disk.size_bytes)
        ),
        format!("  Config  {}", source),
        String::new(),
        "  Partition plan:".into(),
        "  Only the new partitions below will be formatted.".into(),
        String::new(),
    ];

    if let Some(plan) = &cfg.partition_plan {
        lines.push(format!(
            "    Empty space LBA {}-{} ({})",
            plan.extent.start_lba,
            plan.extent.end_lba,
            format_bytes(plan.extent.size_bytes)
        ));
        lines.push(format!(
            "    new EFI/boot    LBA {}-{}   {}",
            plan.boot.first_lba,
            plan.boot.last_lba,
            format_bytes(plan.boot.size_bytes)
        ));
        lines.push(format!(
            "    new root [LUKS2] LBA {}-{}   {}",
            plan.root.first_lba,
            plan.root.last_lba,
            format_bytes(plan.root.size_bytes)
        ));
        if plan.overprovision_bytes > 0 {
            lines.push(format!(
                "    reserved         {}",
                format_bytes(plan.overprovision_bytes)
            ));
        }
    }

    if cfg.overprovision_pct > 0 {
        lines.push(format!("  Overprovisioned  {}%", cfg.overprovision_pct));
    }
    lines.push(String::new());
    lines.push("  Press Enter to begin installation, Esc to go back.".into());

    let p = Paragraph::new(lines.join("\n"))
        .wrap(Wrap { trim: false })
        .block(block("Summary — Review Your Choices"));
    f.render_widget(p, area);
}

fn render_installing(
    f: &mut Frame,
    area: Rect,
    log: &[String],
    scroll: usize,
    done: bool,
    error: bool,
) {
    let spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    let spinner = spinner_chars[log.len() % spinner_chars.len()];

    let (title, title_style) = if done {
        (
            " Installing — Done ✓ ".to_string(),
            Style::default().fg(GREEN).add_modifier(Modifier::BOLD),
        )
    } else if error {
        (
            " Installing — Error ✗ ".to_string(),
            Style::default().fg(RED).add_modifier(Modifier::BOLD),
        )
    } else {
        (
            format!(" Installing {}  ", spinner),
            Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        )
    };

    let border_color = if error {
        RED
    } else if done {
        GREEN
    } else {
        INDIGO
    };

    let outer = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(border_color))
        .title(title)
        .title_style(title_style);

    let inner = outer.inner(area);
    f.render_widget(outer, area);

    let visible = inner.height as usize;
    let start = scroll.saturating_sub(visible.saturating_sub(1));
    let end = (start + visible).min(log.len());

    let items: Vec<ListItem> = log[start..end]
        .iter()
        .map(|l| ListItem::new(format!("  {}", l)))
        .collect();
    f.render_widget(List::new(items), inner);
}
