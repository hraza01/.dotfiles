local wezterm = require 'wezterm'
local act = wezterm.action

-- show only the tab number (1-indexed) with one space of padding
wezterm.on('format-tab-title', function(tab)
  local title = string.format(' %d ', tab.tab_index + 1)
  if tab.is_active then
    return wezterm.format({
      { Background = { Color = '#555555' } },
      { Foreground = { Color = '#ffffff' } },
      { Text = title },
    })
  end
  return wezterm.format({
    { Background = { Color = 'rgba(0,0,0,0)' } },
    { Foreground = { Color = '#aaaaaa' } },
    { Text = title },
  })
end)

return {
  -- fonts
  font = wezterm.font 'JetBrainsMono Nerd Font Propo',
  font_size = 15.0,
  harfbuzz_features = { 'calt=0', 'liga=0' },

  -- window
  window_decorations = 'RESIZE',
  window_padding = { left = 15, right = 15, top = 15, bottom = 15 },
  window_background_opacity = 0.83,
  macos_window_background_blur_radius = 2,

  -- tab bar
  tab_bar_at_bottom = true,
  use_fancy_tab_bar = false,

  -- cursor
  default_cursor = 'SteadyBlock',

  -- colors (overrides on top of the default scheme)
  colors = {
    background = 'black',
    cursor = '#BCB8B4',
    split = '#555555',
    tab_bar = { background = 'rgba(0,0,0,0)' },
  },

  keys = {
    -- splits
    { key = 'd', mods = 'SUPER',       action = act.SplitPane { direction = 'Right' } },
    { key = 'd', mods = 'SUPER|SHIFT', action = act.SplitPane { direction = 'Down' } },

    -- close pane (no confirmation)
    { key = 'w', mods = 'SUPER', action = act.CloseCurrentPane { confirm = false } },

    -- text navigation (readline sequences)
    { key = 'LeftArrow',  mods = 'SUPER', action = act.SendKey { key = 'a', mods = 'CTRL' } },
    { key = 'RightArrow', mods = 'SUPER', action = act.SendKey { key = 'e', mods = 'CTRL' } },
    { key = 'LeftArrow',  mods = 'OPT',   action = act.SendKey { key = 'b', mods = 'ALT' } },
    { key = 'RightArrow', mods = 'OPT',   action = act.SendKey { key = 'f', mods = 'ALT' } },
    { key = 'Backspace',  mods = 'OPT',   action = act.SendKey { key = 'Backspace', mods = 'ALT' } },
    -- opt+d: forward word delete (fn+delete not bindable on this build)
    { key = 'd',          mods = 'OPT',   action = act.SendKey { key = 'd', mods = 'ALT' } },

    -- pane navigation
    { key = 'h', mods = 'OPT', action = act.ActivatePaneDirection 'Left' },
    { key = 'j', mods = 'OPT', action = act.ActivatePaneDirection 'Down' },
    { key = 'k', mods = 'OPT', action = act.ActivatePaneDirection 'Up' },
    { key = 'l', mods = 'OPT', action = act.ActivatePaneDirection 'Right' },

    -- reload config
    { key = 'z', mods = 'OPT', action = act.ReloadConfiguration },
  },
}
