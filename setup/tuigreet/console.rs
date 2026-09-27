//! Opt-in presentation for the pinned dotfiles console theme. Prompts and menus
//! use upstream widgets; console login shortcuts live in keyboard.rs.
use chrono::{Local, TimeZone};
use nix::libc;
use tui::{
  layout::{Alignment, Rect},
  text::Line,
  widgets::Paragraph,
};
use tuigreet_types::Mode;

use super::{Frame, common::style::Themed, util::should_hide_cursor};
use crate::{Greeter, info::capslock_status};

pub fn enabled(greeter: &Greeter) -> bool {
  greeter.loaded_config.as_ref().is_some_and(|c| c.layout.console)
}

// Chrono's Local %Z is a numeric offset. Use libc's current timezone rules for
// the abbreviation, recomputed on every draw so DST/resume cannot stale it.
fn clock_at(timestamp: i64) -> String {
  let now = Local.timestamp_opt(timestamp, 0).single().unwrap();
  let mut zone = [0u8; 64];
  let mut broken_down = std::mem::MaybeUninit::<libc::tm>::uninit();
  let epoch = timestamp as libc::time_t;
  // SAFETY: localtime_r initializes the supplied tm before strftime reads it;
  // strftime receives a bounded, writable buffer and a static NUL-ended format.
  let length = unsafe {
    if libc::localtime_r(&epoch, broken_down.as_mut_ptr()).is_null() {
      0
    } else {
      libc::strftime(zone.as_mut_ptr().cast(), zone.len(), c"%Z".as_ptr(), broken_down.as_ptr())
    }
  };
  let zone = if length == 0 {
    now.format("%:z").to_string()
  } else {
    String::from_utf8_lossy(&zone[..length]).into_owned()
  };
  format!("{} {} {}", now.format("%a %b %d %H:%M:%S"), zone, now.format("%Y"))
}

fn footer(greeter: &Greeter, width: u16) -> Vec<Line<'static>> {
  let clock = greeter.time.then(|| clock_at(Local::now().timestamp()));
  let mut help = vec![];
  if greeter.status_show_caps_lock && capslock_status() {
    help.push("Caps Lock".to_owned());
  }
  let hints: &[&str] = if greeter.working {
    &["Authenticating…"]
  } else {
    match greeter.mode {
      Mode::Username | Mode::Password =>
        &["Esc clears", "Ctrl+U resets", "Enter submits"],
      Mode::Command => &["Esc back", "Ctrl+U clears", "Enter confirms"],
      Mode::Users | Mode::Sessions | Mode::Power | Mode::Background =>
        &["Esc back", "↑/↓ select", "Enter confirms"],
      _ => &["Esc resets"],
    }
  };
  help.extend(hints.iter().map(|s| (*s).to_owned()));
  let combined = clock.iter().chain(help.iter()).cloned().collect::<Vec<_>>().join(" · ");
  if combined.chars().count() <= usize::from(width) {
    return vec![Line::from(combined)];
  }
  // At narrow widths put the clock above the help, rather than stranding the
  // last shortcut alone after a mixed clock/help line. Wrap help by item.
  let mut lines = vec![];
  if let Some(clock) = clock { lines.push(Line::from(clock)); }
  let mut line = String::new();
  for part in help {
    if !line.is_empty() && line.chars().count() + 3 + part.chars().count() > usize::from(width) {
      lines.push(Line::from(std::mem::take(&mut line)));
    }
    if !line.is_empty() { line.push_str(" · "); }
    line.push_str(&part);
  }
  if !line.is_empty() { lines.push(Line::from(line)); }
  lines
}

pub fn draw(greeter: &mut Greeter, f: &mut Frame) {
  let area = f.area();
  if area.width < 40 || area.height < 12 {
    f.render_widget(Paragraph::new("Enlarge the terminal to show the login prompt"), area);
    return;
  }
  let lines = footer(greeter, area.width.saturating_sub(4));
  let footer_height = lines.len() as u16;
  let footer_y = area.bottom().saturating_sub(footer_height + 1);
  let main_area = Rect::new(area.x, area.y, area.width, footer_y.saturating_sub(area.y + 1));
  // Same native dispatch as the ordinary UI, including non-password PAM
  // prompts, processing, error messages and keyboard-accessible menus.
  let cursor = match greeter.mode {
    Mode::Command => super::command::draw_with_area(greeter, f, main_area).ok(),
    Mode::Sessions => greeter.sessions.draw_with_area(greeter, f, main_area).ok(),
    Mode::Power => greeter.powers.draw_with_area(greeter, f, main_area).ok(),
    Mode::Background => greeter.backgrounds.draw_with_area(greeter, f, main_area).ok(),
    Mode::Users => greeter.users.draw_with_area(greeter, f, main_area).ok(),
    Mode::Processing => super::processing::draw_with_area(greeter, f, main_area).ok(),
    _ => super::prompt::draw_with_area(greeter, f, main_area).ok(),
  };
  f.render_widget(
    Paragraph::new(lines).alignment(Alignment::Right).style(greeter.theme.of(&[Themed::Time])),
    Rect::new(area.x + 2, footer_y, area.width - 4, footer_height),
  );
  if !should_hide_cursor(greeter) && let Some((x, y)) = cursor {
    f.set_cursor_position((x.saturating_sub(1), y.saturating_sub(1)));
  }
}
