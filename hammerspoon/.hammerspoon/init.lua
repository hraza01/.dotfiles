-- opt+enter to toggle Ghostty (launch / focus / hide)
-- requires Accessibility permission for Hammerspoon

local ghostty = 'com.mitchellh.ghostty'

local function toggle_ghostty()
  local app = hs.application.get(ghostty)
  local win = app and app:mainWindow()
  if not win then
    -- Reopening also creates a window if Ghostty is running without one.
    hs.application.open(ghostty)
    return
  end
  local front = hs.application.frontmostApplication()
  if front and front:bundleID() == ghostty and win:isStandard() then
    app:hide()
  else
    app:activate(true)
    win:unminimize()
    win:focus()
  end
end

-- pre-launch Ghostty hidden on startup so the first toggle is instant
local function launch_ghostty_hidden()
  if hs.application.get(ghostty) then return end
  hs.timer.doAfter(1, function()
    if hs.application.get(ghostty) then return end
    hs.application.open(ghostty)
    local attempts = 0
    local timer
    timer = hs.timer.doEvery(0.3, function()
      attempts = attempts + 1
      local app = hs.application.get(ghostty)
      if app and app:mainWindow() then
        app:hide()
        timer:stop()
      elseif attempts > 20 then
        timer:stop()
      end
    end)
  end)
end

hs.hotkey.bind({ 'alt' }, 'return', toggle_ghostty)

launch_ghostty_hidden()
