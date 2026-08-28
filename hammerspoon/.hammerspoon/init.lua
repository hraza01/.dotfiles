-- double-tap Control to toggle WezTerm (launch / focus / hide)
-- requires Accessibility permission for Hammerspoon

local wezterm = 'com.github.wez.wezterm'
local double_tap_sec = 0.3

local last_ctrl = 0

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

ctrl_tap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
  if event:getFlags().ctrl then
    local now = hs.timer.secondsSinceEpoch()
    if now - last_ctrl < double_tap_sec then
      last_ctrl = 0
      toggle_wezterm()
    else
      last_ctrl = now
    end
  end
  return false
end)
ctrl_tap:start()

launch_wezterm_hidden()
