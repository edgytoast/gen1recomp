-- Game state stack.  The top state updates; all states draw bottom-up
-- (so a text box can overlay the overworld, a battle replaces it, etc).
-- States are tables with optional enter/exit/update/draw/isOpaque.

local Runtime = require("src.mods.Runtime")

local StateStack = {}

function StateStack:init()
  self.states = {}
end

-- screen.pushed/popped fire after enter/exit so listeners observe the
-- settled state; the wants guard keeps the no-listener path allocation-free

function StateStack:push(state, ...)
  table.insert(self.states, state)
  if state.enter then state:enter(...) end
  if Runtime.wants("screen.pushed") then
    Runtime.emit("screen.pushed", { state = state })
  end
end

function StateStack:pop()
  local state = table.remove(self.states)
  if state and state.exit then state:exit() end
  if state and Runtime.wants("screen.popped") then
    Runtime.emit("screen.popped", { state = state })
  end
  return state
end

function StateStack:top()
  return self.states[#self.states]
end

function StateStack:update(dt)
  local top = self:top()
  if top and top.update then top:update(dt) end
end

-- index of the lowest state drawn this frame (highest opaque, else 1)
local function visibleByDefault() return true end

-- Whether a state draws on the MAIN SCREEN this frame.
--
-- A mod may mirror a state somewhere else -- a headset draws the game's menus
-- as windows standing in the world -- and then the flat draw is a second copy
-- of a thing the player is already looking at. This lets it hide that one
-- draw and nothing else: the state stays on the stack, so update and input
-- ownership do not move, the cursor is still the real menu's cursor, and a
-- state no mod claims keeps drawing exactly as it always did.
--
-- Hiding rather than replacing is the whole point. A mod that forked the menu
-- would own a second copy of its state and the two would drift; this way there
-- is only ever one menu, and the mirror is a view of it.
function StateStack:renderVisible(state)
  if not state then return false end
  if not Runtime.wantsHook("screen.render_visible") then return true end
  return Runtime.call("screen.render_visible", visibleByDefault, state) ~= false
end

-- index of the lowest state drawn this frame (highest opaque, else 1)
--
-- A hidden state cannot be the base: it draws nothing, so the states under it
-- would be covered by a screen that is not there.
function StateStack:visibleBase()
  for i = #self.states, 1, -1 do
    local state = self.states[i]
    if self:renderVisible(state) and state.isOpaque then return i end
  end
  return 1
end

function StateStack:draw()
  for i = self:visibleBase(), #self.states do
    local state = self.states[i]
    if state.draw and self:renderVisible(state) then state:draw() end
  end
end

return StateStack
