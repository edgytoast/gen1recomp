-- Screen id -> factory resolution.  The screens registry (Data.screens)
-- wins; engine screens are the require fallback, so a mod-free boot
-- resolves every id to the exact module it required before.  One cache,
-- dropped with the rest of the asset caches on dev-mode hot reload.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Screens = {}

-- ids whose builtin module is not under src/ui/
local BUILTIN = {
  ManagerState = "src.mods.ManagerState",
}

local cache = {}

local function builtinFor(id)
  return require(BUILTIN[id] or ("src.ui." .. id))
end

local function resolve(game, id)
  local hit = cache[id]
  if hit then return hit end
  local screens = game and game.data and game.data.screens
  local record = screens and screens[id]
  local factory
  if record then
    -- registry record: { new = fn } or a bare function (05-registry-system)
    factory = (type(record) == "function") and { new = record } or record
    factory.__modOwned = true
  else
    factory = builtinFor(id)
  end
  cache[id] = factory
  return factory
end

function Screens.get(game, id)
  return resolve(game, id)
end

-- Make a screen without putting it on the stack.
--
-- Pushing is the usual thing to do with one, and for a long time it was the
-- only thing this offered.  But a screen is also a DESCRIPTION -- the START
-- menu is the list of what the START menu can do -- and a caller that wants
-- to run one of its rows without ever showing the menu has no other way to
-- ask what the rows are.  That is not hypothetical: it is how a mod runs
-- SAVE or LINK from somewhere else, and with no build() the whole flow ends
-- in a refusal beep with nothing to say why.
local function build(game, id, ...)
  local factory = resolve(game, id)
  local inst
  if factory.__modOwned then
    -- a broken mod screen degrades to the builtin, never a dead end
    local ok, result = pcall(factory.new, game, ...)
    if ok and result then
      inst = result
    else
      Logger.error("mod screen '%s' failed: %s -- using builtin",
                   id, tostring(result))
      cache[id] = nil
      inst = builtinFor(id).new(game, ...)
    end
  else
    inst = factory.new(game, ...)
  end
  inst.screenId = inst.screenId or id
  return inst
end

function Screens.build(game, id, ...)
  return build(game, id, ...)
end

function Screens.push(game, id, ...)
  local inst = build(game, id, ...)
  game.stack:push(inst)
  return inst
end

function Screens.invalidate()
  cache = {}
end

Assets.register(Screens.invalidate)

return Screens
