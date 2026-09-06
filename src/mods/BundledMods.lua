-- Mods the app ships with, planted once into the writable mod folder.
--
-- game.love deliberately carries no fused mods: one read straight out of the
-- read-only app bundle cannot be removed, so the manager's Delete does nothing
-- and the mod is back on the next launch -- scripts/build_visionos.sh says as
-- much where it packs the archive. What ships instead is a .zip per mod under
-- bundled_mods/, planted through the same LauncherMods.installZip that an
-- "Import mod .zip" goes through. What lands in mods/<id>/ afterwards is an
-- ordinary installed mod: enabled, disabled or deleted like any other.
--
-- The record is the point of the exercise. Without one, "never installed" and
-- "the user deleted it" look identical, and the seed grows back on every
-- launch -- precisely the behaviour fusing was avoided for. So a mod is
-- planted when it has never been planted, and re-planted only when the app
-- carries a NEWER version AND the old one is still installed. A mod thrown
-- away stays away, however many app updates go by.
--
-- A mod already sitting in mods/<id> that this never planted is left alone for
-- good, and the record says so. That is the developer loop:
-- scripts/push_mod_visionos.sh writes a working copy straight into the mod
-- folder, and an app update must not overwrite it with the older copy baked
-- into the build.
local Json = require("src.link.Json")
local LauncherMods = require("src.mods.LauncherMods")
local Logger = require("src.core.Logger")
local Semver = require("src.mods.Semver")

local BundledMods = {}

BundledMods.DIR = "bundled_mods"
BundledMods.INDEX = "bundled_mods/index.json"
-- Beside the mod folder, not inside it: everything under mods/ is scanned as a
-- mod, and a stray bookkeeping file there is reported as a broken one.
BundledMods.RECORD = "bundled_seeded.json"

local function fs()
  return love and love.filesystem or nil
end

-- What this build ships. love.filesystem.read reaches into game.love as well
-- as the save directory, so the index is read exactly like any other asset.
-- Absent on a build with no bundled mods, which is not an error.
function BundledMods.available()
  local f = fs()
  if not f then return {} end
  local raw = f.read(BundledMods.INDEX)
  if not raw then return {} end
  local ok, list = pcall(Json.decode, raw)
  if not ok or type(list) ~= "table" then return {} end
  local out = {}
  for _, entry in ipairs(list) do
    if type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "" then
      out[#out + 1] = {
        id = entry.id,
        version = tostring(entry.version or "0.0.0"),
        file = entry.file or (BundledMods.DIR .. "/" .. entry.id .. ".zip"),
      }
    end
  end
  return out
end

function BundledMods.record()
  local f = fs()
  if not f then return {} end
  local raw = f.read(BundledMods.RECORD)
  if not raw then return {} end
  local ok, rec = pcall(Json.decode, raw)
  if not ok or type(rec) ~= "table" then return {} end
  return rec
end

local function installed(f, id)
  return f.getInfo(("mods/%s/manifest.json"):format(id)) ~= nil
end

-- What is ACTUALLY installed, out of its own manifest.
--
-- The record's `version` is what shipped when the note was written, which is
-- not the same question and drifts from it: another build of this app -- a
-- TestFlight copy shares the bundle id and therefore the whole data container
-- -- can put an OLDER mod in the folder without touching our note.  Asked of
-- the record, the answer was "current" while 1.5.4 sat on disk under a note
-- saying 2.1.3, and nothing ever repaired it.
local function installedVersion(f, id)
  local raw = f.read(("mods/%s/manifest.json"):format(id))
  if not raw then return nil end
  local ok, m = pcall(Json.decode, raw)
  if not ok or type(m) ~= "table" then return nil end
  return type(m.version) == "string" and m.version or nil
end

local function newer(bundled, seeded)
  local ok, order = pcall(Semver.compare, bundled, seeded)
  if not ok or type(order) ~= "number" then
    -- Unparseable either side: a version we cannot order is not a version we
    -- may overwrite somebody's installed copy for.
    return false
  end
  return order > 0
end

-- Returns { planted = {id...}, skipped = {{id, why}...}, errors = {{id, err}...} }.
-- opts.install overrides the installer (the tests hand it a recorder).
function BundledMods.seed(opts)
  opts = opts or {}
  local result = { planted = {}, skipped = {}, errors = {} }
  local f = fs()
  if not f then return result end
  local install = opts.install or LauncherMods.installZip

  local rec = BundledMods.record()
  local dirty = false
  for _, entry in ipairs(BundledMods.available()) do
    local was = rec[entry.id]
    local here = installed(f, entry.id)
    local act, why

    -- Never seen, and something is already there: remember that it is not
    -- ours, so a delete later stays a delete.  Noted whether or not this
    -- build then upgrades it -- the note is about ownership, the decision
    -- below is about age.
    if type(was) ~= "table" and here then
      rec[entry.id] = { version = entry.version, planted = false }
      was, dirty = rec[entry.id], true
    end

    if not here then
      -- Never planted and nothing here: plant it.  Planted before and gone
      -- now: the player threw it away, and it stays away.
      act = type(was) ~= "table"
      why = act and nil or "removed"
    elseif newer(entry.version, installedVersion(f, entry.id)
                 -- a manifest with no version of its own: for a copy WE
                 -- planted the record knows what went in, and that is a
                 -- better answer than "unorderable, leave it".  For anyone
                 -- else's copy there is nothing to fall back to, and an age
                 -- that cannot be read is not an age to overwrite for.
                 or (was and was.planted and tostring(was.version or "")) or "") then
      -- OLDER THAN WHAT SHIPS, whoever put it there.
      --
      -- A copy this never planted used to be left alone for good, which
      -- protects two things worth protecting: a working copy pushed straight
      -- into the mod folder by the dev script, and a mod the player installed
      -- themselves.  It also meant an app carrying a NEWER mod could not
      -- repair an older one -- and that is not hypothetical: launching a
      -- TestFlight build of this same app, which shares the data container
      -- and ships mods of its own, put 1.5.4 back over a 2.1.3 that had been
      -- pushed, and every launch afterwards said "nothing to plant".
      --
      -- Strictly newer, so both protections survive: the dev loop builds the
      -- bundle from the same checkout it pushes, so the two versions are
      -- equal and nothing is touched, and a copy ahead of the app is left
      -- alone as it always was.
      act = true
    else
      act, why = false, (was and was.planted == false) and "foreign" or "current"
    end

    if act then
      -- replace only when something is there to replace; a fresh plant onto an
      -- empty folder does not need the uninstall pass.
      local ok, err = install(entry.file, { expectId = entry.id, replace = here })
      if ok then
        rec[entry.id] = { version = entry.version, planted = true }
        dirty = true
        result.planted[#result.planted + 1] = entry.id
      else
        result.errors[#result.errors + 1] = { id = entry.id, err = tostring(err) }
      end
    else
      result.skipped[#result.skipped + 1] = { id = entry.id, why = why }
    end
  end

  if dirty then
    local ok, encoded = pcall(Json.encode, rec)
    if ok then f.write(BundledMods.RECORD, encoded) end
  end

  -- Said out loud, both ways.  A plant that quietly does nothing is
  -- indistinguishable from a build that shipped no mods, and that is exactly
  -- the confusion this went through once already.
  for _, id in ipairs(result.planted) do
    Logger.info("bundled mod planted: %s", id)
  end
  for _, entry in ipairs(result.errors) do
    Logger.warn("bundled mod %s could not be planted: %s", entry.id, entry.err)
  end
  if #result.planted == 0 and #result.errors == 0 then
    Logger.info("bundled mods: nothing to plant (%d shipped)", #result.skipped)
  end
  return result
end

return BundledMods
