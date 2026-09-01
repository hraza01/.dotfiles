-- ctrl+enter to toggle WezTerm (launch / focus / hide)
-- requires Accessibility permission for Hammerspoon

local wezterm = 'com.github.wez.wezterm'

local function toggle_wezterm()
  local app = hs.application.find(wezterm)
  if not app then
    hs.application.open(wezterm)
    return
  end
  local front = hs.application.frontmostApplication()
  local win = app:mainWindow()
  if front and front:bundleID() == wezterm and win and win:isStandard() then
    app:hide()
  else
    app:activate(true)
    if win then win:focus() end
  end
end

-- pre-launch WezTerm hidden on startup so the first toggle is instant
local function launch_wezterm_hidden()
  if hs.application.find(wezterm) then return end
  hs.timer.doAfter(1, function()
    hs.application.open(wezterm)
    local attempts = 0
    local timer = hs.timer.doEvery(0.3, function()
      attempts = attempts + 1
      local app = hs.application.find(wezterm)
      if app and app:mainWindow() then
        app:hide()
        timer:stop()
      elseif attempts > 20 then
        timer:stop()
      end
    end)
  end)
end

hs.hotkey.bind({ 'ctrl' }, 'return', toggle_wezterm)

launch_wezterm_hidden()
