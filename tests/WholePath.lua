-- Tests the addon's modules together, with nothing replaced but the game: the real Profiles,
-- ChatSettings and ExportString over the model of the client in tests/FakeChat.lua. Saving a
-- setup on one character, applying it on another, and moving it through an export string should
-- each leave nothing different.

local helpers = dofile("tests/helpers.lua")
local Check, Equal = helpers.Check, helpers.Equal
local FakeChat = dofile("tests/FakeChat.lua")

FakeChat.Install()

-- Stand-ins for the rest of the game.
local characterName
function UnitName()
	return characterName
end
function GetNormalizedRealmName()
	return "Realm"
end
function strlenutf8(text)
	local _, count = text:gsub("[^\128-\191]", "")
	return count
end
CopyTable = helpers.DeepCopy
function InCombatLockdown()
	return false
end
C_Timer = {
	After = function(_, callback)
		callback()
	end,
}
local frame
function CreateFrame()
	frame = { registered = {} }
	function frame:RegisterEvent(event)
		self.registered[event] = true
	end
	function frame:UnregisterEvent(event)
		self.registered[event] = nil
	end
	function frame:SetScript(_, script)
		self.script = script
	end
	return frame
end
local function Fire(event, ...)
	if frame.registered[event] then
		frame.script(frame, event, ...)
	end
end

-- Encoding is the client's, so it's a stand-in: the text holds a token for a stored copy.
local encoded = {}
C_EncodingUtil = {
	SerializeCBOR = function(data)
		table.insert(encoded, helpers.DeepCopy(data))
		return tostring(#encoded)
	end,
	EncodeBase64 = function(text)
		return text
	end,
	DecodeBase64 = function(text)
		return text
	end,
	DeserializeCBOR = function(text)
		return helpers.DeepCopy(encoded[tonumber(text)])
	end,
}

-- Logs `name` in with the client set up as `setup`, loading the addon the way the client does.
-- ChatProfilesDB carries over between logins, as saved variables do.
local function LogIn(name, setup)
	characterName = name
	FakeChat.Load(setup)
	local ns = {}
	for _, file in ipairs({ "ChatSettings", "ExportString", "Profiles" }) do
		helpers.LoadAddonFile("ChatProfiles/" .. file .. ".lua", ns)
	end
	Fire("ADDON_LOADED", "ChatProfiles")
	Fire("PLAYER_LOGIN")
	return ns
end

local function Texts(differences)
	local texts = {}
	for i, difference in ipairs(differences or {}) do
		texts[i] = difference.text
	end
	return texts
end

local function Docked(name, fields)
	local window = { key = "name:" .. name, name = name, docked = true, locked = true }
	for field, value in pairs(fields or {}) do
		window[field] = value
	end
	return window
end

local MAIN_SETUP = {
	windows = {
		{ key = "window:1", name = "General", docked = true, fontSize = 16, messageGroups = { "SAY", "GUILD" } },
		{ key = "window:2", name = "Combat Log", docked = true, locked = true },
		Docked("party", { messageGroups = { "PARTY" }, channels = { { name = "Trade", zoneChannelID = 2 } } }),
		Docked("trade", { channels = { { name = "cpTEST", zoneChannelID = 0 } } }),
		{
			key = "name:whispers",
			name = "whispers",
			docked = false,
			point = "TOPLEFT",
			xOffset = 0.1,
			yOffset = -0.25,
			width = 430,
			height = 120,
			messageGroups = { "WHISPER" },
		},
	},
	colors = { SAY = { r = 1, g = 0.5, b = 0, classColoredNames = true }, GUILD = { r = 0, g = 1, b = 0 } },
}
local OTHER_SETUP = {
	windows = { { key = "window:1", name = "General", docked = true }, Docked("loot"), Docked("party") },
	colors = { SAY = { r = 1, g = 1, b = 1, classColoredNames = false }, GUILD = { r = 1, g = 1, b = 1 } },
}

-- Saving on one character

ChatProfilesDB = nil
local Profiles = LogIn("First", MAIN_SETUP).Profiles
Equal(Profiles.SaveAsNew("Main"), "Main", "saving the setup as a new profile failed")
Equal(Texts(Profiles.Differences()), {}, "a profile just saved differs from the setup it came from")

-- A change in the game's own chat UI, then logout.
FCF_OpenNewWindow("loot", true)
_G.ChatFrame1:AddMessageGroup("LOOT")
Equal(
	Texts(Profiles.Differences()),
	{ 'Extra tab "loot"', "General: also shows LOOT messages" },
	"a change in the game wasn't listed"
)
Fire("PLAYER_LOGOUT")

-- Applying on another character

ChatProfilesDB.profileByCharacter["Second-Realm"] = "Main"
Profiles = LogIn("Second", OTHER_SETUP).Profiles
Check(not Profiles.LastApplyFailed(), "the login apply on the second character failed")
Equal(Texts(Profiles.Differences()), {}, "the second character doesn't match the profile after login")
Check(Profiles.CanSave(), "Save now was unavailable after a clean login apply")

-- Moving it through an export string

local ns = LogIn("Third", OTHER_SETUP)
Profiles = ns.Profiles
local imported, reason = ns.ExportString.Import(ns.ExportString.Export(ChatProfilesDB.profiles.Main))
Check(imported ~= nil, "the saved profile failed its own import check: " .. tostring(reason))
Equal(Profiles.AddImported("Copy", imported), "Copy", "adding the imported profile failed")
Equal(ChatProfilesDB.profiles.Copy, ChatProfilesDB.profiles.Main, "the profile changed on its way through an export")
Equal(Texts(Profiles.Select("Copy")), {}, "selecting the imported profile left differences")
Equal(Texts(Profiles.Differences()), {}, "the third character doesn't match the imported profile")

-- Taking the first character off the profile leaves its settings, and the profile, alone.

Profiles = LogIn("First", MAIN_SETUP).Profiles
local savedMain = helpers.DeepCopy(ChatProfilesDB.profiles.Main)
Profiles.Select(nil)
FCF_OpenNewWindow("pvp", true)
Fire("PLAYER_LOGOUT")
Equal(ChatProfilesDB.profiles.Main, savedMain, "a character that left the profile still saved into it")

return helpers.Failures()
