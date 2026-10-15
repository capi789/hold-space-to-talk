-- Hold Space to Talk for the Claude and ChatGPT Mac apps (Hammerspoon).
--   Hold Space   -> the app's mic turns on, your Mac's sound is muted and Spotify pauses.
--   Tap Space    -> mic off, the words stay in the box, sound comes back.
--   Return       -> mic off, waits for the words to land, then sends (one press).
-- Only active while Claude or ChatGPT is the app in front; everywhere else Space is just Space.
-- Updates itself from GitHub. Log: ~/.hammerspoon/hold-space-to-talk/log.txt
-- https://github.com/capi789/hold-space-to-talk

local VERSION = 1
local REPO_RAW = "https://raw.githubusercontent.com/capi789/hold-space-to-talk/main/"
local DIR = hs.configdir .. "/hold-space-to-talk"
local HOLD = 0.35 -- seconds Space must be held before the mic turns on

-- The apps this works in, and what their mic button is called while off / while listening.
-- When an app update renames its mic, this table is the only thing that needs changing.
local APPS = {
  Claude  = { role = "AXCheckBox", off = { ["Press and hold to record"] = true }, on = { ["Stop dictation"] = true } },
  ChatGPT = { role = "AXButton",   off = { ["Dictate"] = true },                  on = { ["Stop dictation"] = true, ["Stop dictating"] = true, ["Done"] = true } },
}

-- Everything long-lived hangs off this global so Lua never garbage-collects the key listener.
if HoldSpaceToTalk and HoldSpaceToTalk.stop then pcall(HoldSpaceToTalk.stop) end
local S = { version = VERSION, axOnFor = {}, listening = false }
HoldSpaceToTalk = S

local SPACE = hs.keycodes.map.space
local RETURN = hs.keycodes.map["return"]
local MINE = 4242 -- marks keys we type ourselves, so we don't catch them again
local T = hs.eventtap.event.types
local P = hs.eventtap.event.properties

local function log(msg)
  local path = DIR .. "/log.txt"
  local attr = hs.fs.attributes(path)
  if attr and attr.size > 200000 then os.remove(path) end
  local f = io.open(path, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg .. "\n"); f:close() end
end

local function frontApp()
  local app = hs.application.frontmostApplication()
  local name = app and app:name()
  return name and APPS[name] and name or nil
end

-- Electron apps hide their buttons from accessibility until asked; the tree takes a few seconds to build.
local function enableAX(name, app)
  if app and S.axOnFor[name] ~= app:pid() then
    pcall(function() hs.axuielement.applicationElement(app):setAttributeValue("AXManualAccessibility", true) end)
    S.axOnFor[name] = app:pid()
    log("accessibility on for " .. name)
  end
end

local function attr(el, key)
  local ok, v = pcall(function() return el:attributeValue(key) end)
  if ok then return v end
end

local function isMic(el, cfg)
  local d = attr(el, "AXDescription")
  return d and (cfg.off[d] or cfg.on[d]) and attr(el, "AXRole") == cfg.role
end

-- Best way to find the right mic: start at the message box you're typing in and look around it.
local function micNearFocus(cfg)
  local focused = attr(hs.axuielement.systemWideElement(), "AXFocusedUIElement")
  if not focused then return nil end
  local role = attr(focused, "AXRole")
  if role ~= "AXTextArea" and role ~= "AXTextField" then return nil end
  local node = focused
  for _ = 1, 10 do
    node = attr(node, "AXParent")
    if not node then return nil end
    local found, seen = nil, 0
    local function walk(el, depth)
      if found or depth > 12 or seen > 600 then return end
      seen = seen + 1
      if isMic(el, cfg) then found = el return end
      local kids = attr(el, "AXChildren")
      if kids then for _, k in ipairs(kids) do walk(k, depth + 1) if found then return end end end
    end
    walk(node, 0)
    if found then return found end
  end
end

-- Fallback: search only the strip along the bottom of the window (the whole window takes 25s+).
local function findMic(name)
  name = name or frontApp()
  local cfg = name and APPS[name]
  local app = name and hs.application.get(name)
  if not (cfg and app) then return nil end
  enableAX(name, app)
  if frontApp() == name then local near = micNearFocus(cfg); if near then return near end end
  local w = app:focusedWindow() or app:mainWindow()
  local win = w and hs.axuielement.windowElement(w)
  local wf = win and attr(win, "AXFrame")
  if not wf then return nil end
  local zoneTop = wf.y + wf.h - 220
  local found, seen = nil, 0
  local function walk(el, depth)
    if found or depth > 60 or seen > 4000 then return end
    seen = seen + 1
    local f = attr(el, "AXFrame")
    if f and f.h > 0 and (f.y + f.h) < zoneTop then return end
    if isMic(el, cfg) then found = el return end
    local kids = attr(el, "AXChildren")
    if kids then for i = #kids, 1, -1 do walk(kids[i], depth + 1) if found then return end end end
  end
  walk(win, 0)
  return found
end

local function micOn(el, name)
  local cfg = APPS[name or frontApp() or ""]
  local d = cfg and attr(el, "AXDescription")
  return d ~= nil and cfg.on[d] == true
end

local function clickAt(pt)
  local back = hs.mouse.absolutePosition()
  hs.mouse.absolutePosition(pt)
  hs.eventtap.event.newMouseEvent(T.leftMouseDown, pt):setProperty(P.mouseEventClickState, 1):post()
  hs.eventtap.event.newMouseEvent(T.leftMouseUp, pt):setProperty(P.mouseEventClickState, 1):post()
  hs.timer.doAfter(0.05, function() hs.mouse.absolutePosition(back) end)
end

local function clickMic(el)
  local f = attr(el, "AXFrame")
  if not f then return end
  S.micPt = { x = f.x + f.w / 2, y = f.y + f.h / 2 }
  clickAt(S.micPt)
end

-- Sound: mute the Mac while you talk. Remember only that WE muted it (saved to disk, so a crash or
-- restart still turns the sound back on). Spotify is paused and resumed too.
local function osa(script, cb)
  local t = hs.task.new("/usr/bin/osascript", function(_, out) if cb then cb(out or "") end end, { "-e", script })
  t:start()
  return t
end

local function quiet()
  local out = hs.audiodevice.defaultOutputDevice()
  if out and not out:outputMuted() then out:setOutputMuted(true); hs.settings.set("hstWeMuted", true) end
  S.pausedSpotify = false
  if hs.application.get("Spotify") then
    S.spotTask = osa('tell application "Spotify"\nif player state is playing then\npause\nreturn "paused"\nend if\nend tell',
      function(o) if o:find("paused") then S.pausedSpotify = true end end)
  end
end

local function unmuteIfWeMuted(why)
  if not hs.settings.get("hstWeMuted") then return end
  local out = hs.audiodevice.defaultOutputDevice()
  if out then out:setOutputMuted(false) end
  hs.settings.set("hstWeMuted", false)
  log("sound back on (" .. why .. ")")
end

local function loud()
  if not S.listening then unmuteIfWeMuted("mic off") end
  if S.pausedSpotify then osa('tell application "Spotify" to play'); S.pausedSpotify = false end
end

local function postKey(key)
  for _, isDown in ipairs({ true, false }) do
    local ev = hs.eventtap.event.newKeyEvent({}, key, isDown)
    ev:setProperty(P.eventSourceUserData, MINE)
    ev:post()
  end
end

local function startListening()
  S.holdTimer = nil
  S.app = frontApp()
  local el = findMic(S.app) or S.micEl
  if not el then log("mic not found in " .. tostring(S.app) .. " -> typed a space"); postKey("space"); return end
  S.micEl = el
  if not micOn(el, S.app) then clickMic(el) end
  S.listening, S.since, S.seenOn = true, hs.timer.secondsSinceEpoch(), false
  log("mic ON in " .. tostring(S.app))
  quiet()
  -- Learn what this app calls its mic while listening, in case an update renamed it.
  hs.timer.doAfter(0.8, function()
    if not (S.listening and S.micPt and APPS[S.app]) then return end
    local d = attr(hs.axuielement.systemElementAtPosition(S.micPt), "AXDescription")
    if d and d ~= "" and not APPS[S.app].off[d] and not APPS[S.app].on[d] then APPS[S.app].on[d] = true; log("learned on-label: " .. d) end
  end)
end

local function stopListening(why)
  local el = findMic(S.app) or S.micEl
  if el and micOn(el, S.app) then clickMic(el)
  elseif S.listening and S.micPt then clickAt(S.micPt) end
  S.listening = false
  log("mic OFF (" .. why .. ")")
  hs.timer.doAfter(0.4, loud)
end

-- The message box's text, to see when dictated words have finished arriving.
local function promptText()
  local focused = attr(hs.axuielement.systemWideElement(), "AXFocusedUIElement")
  local role = focused and attr(focused, "AXRole")
  if role == "AXTextArea" or role == "AXTextField" then return tostring(attr(focused, "AXValue") or "") end
  local app = hs.application.get(S.app or "Claude")
  local w = app and (app:focusedWindow() or app:mainWindow())
  local win = w and hs.axuielement.windowElement(w)
  local wf = win and attr(win, "AXFrame")
  if not wf then return nil end
  local zoneTop, found = wf.y + wf.h - 260, nil
  local function walk(el, depth)
    if found or depth > 60 then return end
    local f = attr(el, "AXFrame")
    if f and f.h > 0 and (f.y + f.h) < zoneTop then return end
    local r = attr(el, "AXRole")
    if r == "AXTextArea" or r == "AXTextField" then found = el return end
    local kids = attr(el, "AXChildren")
    if kids then for i = #kids, 1, -1 do walk(kids[i], depth + 1) if found then return end end end
  end
  walk(win, 0)
  return found and tostring(attr(found, "AXValue") or "") or nil
end

-- Return while talking in Claude: stop the mic, wait until the words land and settle, then send.
local function sendAfterDictation()
  stopListening("return -> send")
  local before = promptText()
  local last, stableSince, started, arrived = before, hs.timer.secondsSinceEpoch(), hs.timer.secondsSinceEpoch(), false
  S.sendWait = hs.timer.doEvery(0.2, function()
    local now = hs.timer.secondsSinceEpoch()
    local t = promptText()
    if t ~= last then last, stableSince = t, now end
    if t ~= before then arrived = true end
    local hasText = last and last:gsub("%s", "") ~= ""
    if (arrived and now - stableSince >= 0.8) or (hasText and now - stableSince >= 1.5) or now - started > 12 then
      S.sendWait:stop(); S.sendWait = nil
      postKey("return")
      log("sent after dictation")
    end
  end)
end

S.tap = hs.eventtap.new({ T.keyDown, T.keyUp }, function(e)
  local code, down = e:getKeyCode(), e:getType() == T.keyDown
  if e:getProperty(P.eventSourceUserData) == MINE then return false end
  if code == RETURN and down and S.listening then
    if S.app == "Claude" then hs.timer.doAfter(0, sendAfterDictation); return true end
    -- ChatGPT sends on Return by itself; just keep our state in step.
    S.listening = false; log("mic OFF (return)"); hs.timer.doAfter(0.4, loud); return false
  end
  if code ~= SPACE then return false end
  local m = e:getFlags()
  if m.cmd or m.alt or m.ctrl or m.shift or m.fn then return false end
  if down then
    if e:getProperty(P.keyboardEventAutorepeat) ~= 0 then return S.holdTimer ~= nil or S.swallowUp end
    if not frontApp() then return false end
    if S.listening or (S.micEl and micOn(S.micEl)) then
      S.swallowUp = true
      hs.timer.doAfter(0, function() stopListening("space") end)
      return true
    end
    S.holdTimer = hs.timer.doAfter(HOLD, function() S.swallowUp = true; startListening() end)
    return true
  end
  if S.holdTimer then S.holdTimer:stop(); S.holdTimer = nil; postKey("space"); return true end -- quick tap: a space
  if S.swallowUp then S.swallowUp = false; return true end
  return false
end)
S.tap:start()

-- Switch accessibility on the moment Claude or ChatGPT opens or comes to the front (also after an app
-- update relaunches it), so the first press always finds the mic.
S.appWatch = hs.application.watcher.new(function(name, event, app)
  if APPS[name] and (event == hs.application.watcher.launched or event == hs.application.watcher.activated) then enableAX(name, app) end
end)
S.appWatch:start()
for name in pairs(APPS) do enableAX(name, hs.application.get(name)) end

unmuteIfWeMuted("startup")

S.timers = {
  -- Never leave the Mac muted: if the mic isn't on, put the sound back.
  hs.timer.doEvery(3, function() if not S.listening and not S.sendWait then unmuteIfWeMuted("guard") end end),
  -- Keep the mic found in the background so a press never has to search.
  hs.timer.doEvery(1.5, function() if not S.holdTimer and not S.listening and frontApp() then S.micEl = findMic() end end),
  -- Mic turned off another way (a click, Return)? Bring the sound back anyway.
  hs.timer.doEvery(0.5, function()
    if not (S.listening and S.micPt and APPS[S.app]) then return end
    local d = attr(hs.axuielement.systemElementAtPosition(S.micPt), "AXDescription")
    if not d then return end
    if APPS[S.app].on[d] then S.seenOn = true return end
    if APPS[S.app].off[d] and S.seenOn and hs.timer.secondsSinceEpoch() - (S.since or 0) > 1.5 then
      S.listening = false; log("mic went off elsewhere"); hs.timer.doAfter(0.3, loud)
    end
  end),
  -- macOS switches a key listener off if it's ever slow; switch it back on.
  hs.timer.doEvery(2, function() if not S.tap:isEnabled() then S.tap:start(); log("listener re-enabled") end end),
}

-- Auto-update: check GitHub at start and every 6 hours; install a newer version and reload.
local function checkForUpdate()
  hs.http.asyncGet(REPO_RAW .. "VERSION?t=" .. os.time(), nil, function(status, body)
    local remote = status == 200 and tonumber((body or ""):match("%d+"))
    if not remote or remote <= VERSION then return end
    hs.http.asyncGet(REPO_RAW .. "holdspace.lua?t=" .. os.time(), nil, function(st, code)
      if st ~= 200 or not code or not code:find("HoldSpaceToTalk", 1, true) or not load(code) then log("update " .. remote .. " failed to download") return end
      local tmp = DIR .. "/holdspace.lua.new"
      local f = io.open(tmp, "w")
      if not f then return end
      f:write(code); f:close()
      os.rename(tmp, DIR .. "/holdspace.lua")
      log("updated " .. VERSION .. " -> " .. remote)
      local function reloadWhenIdle()
        if S.listening or S.sendWait or S.holdTimer then hs.timer.doAfter(5, reloadWhenIdle) else hs.reload() end
      end
      reloadWhenIdle()
    end)
  end)
end
S.updateTimer = hs.timer.doAfter(10, checkForUpdate)
S.updateEvery = hs.timer.doEvery(6 * 3600, checkForUpdate)

function S.stop()
  if S.tap then S.tap:stop() end
  if S.appWatch then S.appWatch:stop() end
  for _, t in ipairs(S.timers or {}) do t:stop() end
  if S.updateTimer then S.updateTimer:stop() end
  if S.updateEvery then S.updateEvery:stop() end
end
S.findMic = findMic

hs.autoLaunch(true)
if not hs.accessibilityState() then
  hs.accessibilityState(true)
  hs.alert.show("Hold Space to Talk: allow Hammerspoon in Privacy & Security > Accessibility", 8)
end
log("started v" .. VERSION)
hs.alert.show("Hold Space to Talk is on (Claude & ChatGPT)")
