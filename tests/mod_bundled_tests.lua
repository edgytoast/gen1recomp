-- Seeding the mods an app build ships with.
--
-- Every case here is really one question: after the app has planted a mod
-- once, can the player get rid of it?  Fusing a mod into game.love fails that
-- question, which is why the build does not; these checks are what keep the
-- replacement from failing it in a quieter way.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local BundledMods = require("src.mods.BundledMods")

local S = require("tests.harness").suite("bundled mods")
local check = S.check

local savedFs = love.filesystem

-- A filesystem per case, so one case cannot leave a file lying in the next.
local function memfs(seed)
  local files = {}
  for name, body in pairs(seed or {}) do files[name] = body end
  return {
    files = files,
    read = function(name) return files[name] end,
    write = function(name, body) files[name] = body return true end,
    remove = function(name) files[name] = nil return true end,
    getInfo = function(name)
      if files[name] then return { type = "file" } end
      local prefix = name .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
  }
end

local function index(entries)
  return Json.encode(entries)
end

-- An installer that records what it was asked to do instead of doing it.
local function recorder(fail)
  local calls = {}
  return calls, function(file, opts)
    calls[#calls + 1] = { file = file, opts = opts or {} }
    if fail then return nil, "no" end
    return { id = (opts or {}).expectId }
  end
end

local function whyFor(result, id)
  for _, entry in ipairs(result.skipped) do
    if entry.id == id then return entry.why end
  end
  return nil
end

-- ------- nothing bundled
love.filesystem = memfs({})
local result = BundledMods.seed()
check(#result.planted == 0 and #result.errors == 0,
  "a build with no bundled_mods/index.json plants nothing and does not complain")

-- ------- first launch: the mod is planted
local fsA = memfs({
  ["bundled_mods/index.json"] = index({
    { id = "DRAMATIC_SHAPE", version = "1.5.4",
      file = "bundled_mods/DRAMATIC_SHAPE.zip" },
  }),
})
love.filesystem = fsA
local callsA, installA = recorder(false)
result = BundledMods.seed({ install = installA })
check(#result.planted == 1 and result.planted[1] == "DRAMATIC_SHAPE",
  "a mod this build ships and the folder lacks is planted")
check(callsA[1] and callsA[1].file == "bundled_mods/DRAMATIC_SHAPE.zip",
  "planted from the .zip the index names")
check(callsA[1].opts.expectId == "DRAMATIC_SHAPE",
  "and refuses a .zip whose manifest carries a different id")
check(callsA[1].opts.replace ~= true,
  "no replace pass on an empty folder -- there is nothing to uninstall")
check(fsA.files["bundled_seeded.json"] ~= nil, "the plant is recorded")
check(fsA.files["mods/bundled_seeded.json"] == nil,
  "the record sits beside mods/, not inside it, where it would be scanned as a mod")

-- ------- second launch: nothing happens twice
fsA.files["mods/DRAMATIC_SHAPE/manifest.json"] = "{}"
local callsB, installB = recorder(false)
result = BundledMods.seed({ install = installB })
check(#callsB == 0, "an installed mod at the shipped version is not planted again")
check(whyFor(result, "DRAMATIC_SHAPE") == "current", "and says why")

-- ------- the player deletes it: it stays deleted
fsA.files["mods/DRAMATIC_SHAPE/manifest.json"] = nil
local callsC, installC = recorder(false)
result = BundledMods.seed({ install = installC })
check(#callsC == 0, "a mod the player deleted does not grow back on the next launch")
check(whyFor(result, "DRAMATIC_SHAPE") == "removed", "and the reason is the record, not luck")

-- ------- and it stays deleted across an app update that carries a newer one
fsA.files["bundled_mods/index.json"] = index({
  { id = "DRAMATIC_SHAPE", version = "2.0.0",
    file = "bundled_mods/DRAMATIC_SHAPE.zip" },
})
local callsD, installD = recorder(false)
result = BundledMods.seed({ install = installD })
check(#callsD == 0,
  "a newer bundled version is not an excuse to reinstall what the player threw away")

-- ------- an update reaches a mod that is still installed
local fsE = memfs({
  ["bundled_mods/index.json"] = index({
    { id = "DRAMATIC_SHAPE", version = "2.0.0",
      file = "bundled_mods/DRAMATIC_SHAPE.zip" },
  }),
  ["bundled_seeded.json"] = Json.encode({
    DRAMATIC_SHAPE = { version = "1.5.4", planted = true },
  }),
  ["mods/DRAMATIC_SHAPE/manifest.json"] = "{}",
})
love.filesystem = fsE
local callsE, installE = recorder(false)
result = BundledMods.seed({ install = installE })
check(#result.planted == 1, "a newer bundled version updates the mod it planted")
check(callsE[1] and callsE[1].opts.replace == true,
  "through replace, so the old files do not survive under the new ones")

-- ------- a copy that was here first is left alone, for good
local fsF = memfs({
  ["bundled_mods/index.json"] = index({
    { id = "DRAMATIC_SHAPE", version = "1.5.4",
      file = "bundled_mods/DRAMATIC_SHAPE.zip" },
  }),
  ["mods/DRAMATIC_SHAPE/manifest.json"] = "{}",
})
love.filesystem = fsF
local callsF, installF = recorder(false)
result = BundledMods.seed({ install = installF })
check(#callsF == 0, "a mod already installed by hand is not overwritten by the build's copy")
check(whyFor(result, "DRAMATIC_SHAPE") == "foreign", "and is marked as somebody else's")

fsF.files["bundled_mods/index.json"] = index({
  { id = "DRAMATIC_SHAPE", version = "9.9.9",
    file = "bundled_mods/DRAMATIC_SHAPE.zip" },
})
local callsG, installG = recorder(false)
result = BundledMods.seed({ install = installG })
check(#callsG == 0,
  "still left alone when the app ships a newer one -- this is the push_mod_visionos.sh loop")

-- ------- a failed plant is not recorded as done
local fsH = memfs({
  ["bundled_mods/index.json"] = index({
    { id = "deutsch", version = "0.1.0", file = "bundled_mods/deutsch.zip" },
  }),
})
love.filesystem = fsH
local _, installH = recorder(true)
result = BundledMods.seed({ install = installH })
check(#result.errors == 1 and result.errors[1].id == "deutsch",
  "a .zip that will not install is reported")
local afterFail = fsH.files["bundled_seeded.json"]
check(afterFail == nil or not Json.decode(afterFail).deutsch,
  "and not written down as planted, so the next launch tries again")

-- ------- unorderable versions never overwrite anything
local fsI = memfs({
  ["bundled_mods/index.json"] = index({
    { id = "deutsch", version = "not-a-version", file = "bundled_mods/deutsch.zip" },
  }),
  ["bundled_seeded.json"] = Json.encode({
    deutsch = { version = "0.1.0", planted = true },
  }),
  ["mods/deutsch/manifest.json"] = "{}",
})
love.filesystem = fsI
local callsI, installI = recorder(false)
result = BundledMods.seed({ install = installI })
check(#callsI == 0,
  "a version that cannot be ordered is not treated as newer than what is installed")

love.filesystem = savedFs
S.finish()
