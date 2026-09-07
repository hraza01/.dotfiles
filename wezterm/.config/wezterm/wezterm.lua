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
  font = wezterm.font 'JetBrains Mono',
  font_size = 15.0,
  harfbuzz_features = { 'calt=0', 'liga=0' },

  -- window
  window_decorations = 'RESIZE',
  window_padding = { left = 15, right = 15, top = 15, bottom = 15 },
  window_background_opacity = 0.83,

  -- tab bar
  tab_bar_at_bottom = true,
  use_fancy_tab_bar = false,

  -- cursor
  default_cursor_style = 'SteadyBlock',

  -- colors (overrides on top of the default scheme)
  colors = {
    background = 'black',
    cursor_bg = '#BCB8B4',
    cursor_fg = 'black',
    split = '#555555',
    tab_bar = { background = 'rgba(0,0,0,0)' },
  },

  keys = {
    -- new tab (like Chrome/Firefox)
    { key = 't', mods = 'CTRL', action = act.SpawnTab 'CurrentPaneDomain' },

    -- close tab (like Chrome/Firefox — no confirmation dialog)
    { key = 'w', mods = 'CTRL', action = act.CloseCurrentTab { confirm = false } },

    -- splits
    { key = 'd', mods = 'CTRL|SHIFT',       action = act.SplitPane { direction = 'Right' } },
    { key = 'd', mods = 'CTRL|SHIFT|ALT',   action = act.SplitPane { direction = 'Down' } },

    -- close pane (no confirmation)
    { key = 'w', mods = 'CTRL|SHIFT|ALT', action = act.CloseCurrentPane { confirm = false } },

    -- text navigation (readline sequences)
    { key = 'LeftArrow',  mods = 'CTRL|SHIFT', action = act.SendKey { key = 'a', mods = 'CTRL' } },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.SendKey { key = 'e', mods = 'CTRL' } },
    { key = 'LeftArrow',  mods = 'ALT',        action = act.SendKey { key = 'b', mods = 'ALT' } },
    { key = 'RightArrow', mods = 'ALT',        action = act.SendKey { key = 'f', mods = 'ALT' } },
    { key = 'Backspace',  mods = 'ALT',        action = act.SendKey { key = 'Backspace', mods = 'ALT' } },
    { key = 'd',          mods = 'ALT',        action = act.SendKey { key = 'd', mods = 'ALT' } },

    -- pane navigation
    { key = 'h', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
    { key = 'j', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },
    { key = 'k', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
    { key = 'l', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },

    -- reload config
    { key = 'z', mods = 'ALT', action = act.ReloadConfiguration },

    -- disable wezterm's default Alt+Enter fullscreen toggle
    { key = 'Enter', mods = 'ALT', action = act.DisableDefaultAssignment },

    -- disable wezterm's default Super+W close-tab (use Alt+W via sway instead)
    { key = 'w', mods = 'SUPER', action = act.DisableDefaultAssignment },
  },
}
