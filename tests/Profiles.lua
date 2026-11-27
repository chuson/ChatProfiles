-- Tests for Profiles: when saves happen and when they're skipped, unsaved changes, switching,
-- names, and the login apply.

local helpers = dofile("tests/helpers.lua")
local Check, Equal = helpers.Check, helpers.Equal

local CATEGORIES = { "tabs", "messagesAndChannels", "fontAndBackground", "colors" }
local WINDOW_CATEGORIES = { "tabs", "messagesAndChannels", "fontAndBackground" }

local function AllOn()
	return { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true }
end

-- The game's chat setup, one value per category, so a test can change one category at a time.
local game
-- Categories whose settings an apply can't change, to make an apply fail.
local stuck
-- Set by a test: the first error the next applies return, or that they raise an error instead
-- of returning, as when Read or Diff hits something unexpected.
local applyError, applyRaises

-- A stand-in for ChatSettings over `game`. Profiles only stores what Read returns and passes it
-- back, so `windows` here is keyed by category instead of being a list of tabs.
local function Value(settings, category)
	if category == "colors" then
		return settings.colors
	end
	return settings.windows and settings.windows[category]
end

local FakeChatSettings = {}
function FakeChatSettings.Read(categories)
	local live = { windows = {}, duplicateTabNames = {} }
	for _, category in ipairs(WINDOW_CATEGORIES) do
		if categories[category] then
			live.windows[category] = game[category]
		end
	end
	if categories.colors then
		live.colors = game.colors
	end
	return live
end
-- Like the real Diff, a category with nothing saved has no differences.
function FakeChatSettings.Diff(live, profile, categories)
	categories = categories or profile.categories
	local differences = {}
	for _, category in ipairs(CATEGORIES) do
		local saved = Value(profile, category)
		if categories[category] and saved ~= nil and saved ~= Value(live, category) then
			table.insert(differences, { text = category .. " differs" })
		end
	end
	return differences
end
function FakeChatSettings.Apply(profile)
	if applyRaises then
		error("unexpected profile", 0)
	end
	for _, category in ipairs(CATEGORIES) do
		local saved = Value(profile, category)
		if profile.categories[category] and saved ~= nil and not stuck[category] then
			game[category] = saved
		end
	end
	return FakeChatSettings.Diff(FakeChatSettings.Read(profile.categories), profile), applyError
end

-- A profile with every saved category set to `value`.
local function Settings(value, categories)
	categories = categories or AllOn()
	local profile = { categories = categories, windows = {} }
	for _, category in ipairs(WINDOW_CATEGORIES) do
		if categories[category] then
			profile.windows[category] = value
		end
	end
	if categories.colors then
		profile.colors = value
	end
	return profile
end

local function SetGame(value)
	for _, category in ipairs(CATEGORIES) do
		game[category] = value
	end
end

local function Texts(differences)
	local texts = {}
	for i, difference in ipairs(differences) do
		texts[i] = difference.text
	end
	return texts
end

-- Stand-ins for the game.
local CHARACTER = "Tester-Realm"
function UnitName()
	return "Tester"
end
function GetNormalizedRealmName()
	return "Realm"
end
-- Counts every byte that doesn't continue a UTF-8 character.
function strlenutf8(text)
	local _, count = text:gsub("[^\128-\191]", "")
	return count
end
CopyTable = helpers.DeepCopy

local inCombat
function InCombatLockdown()
	return inCombat
end

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

C_Timer = {
	After = function(_, callback)
		callback()
	end,
}

-- Fires an event the addon registered for. What the addon prints is kept in `printed`. Like
-- the client, an error in the handler is caught, and it fails the test unless the test made
-- applies raise errors on purpose.
local printed
local function Fire(event, ...)
	if not frame.registered[event] then
		return
	end
	local realPrint = print
	print = function(text)
		table.insert(printed, text)
	end
	local ok, err = pcall(frame.script, frame, event, ...)
	print = realPrint
	if not ok and not applyRaises then
		helpers.Fail(event .. " raised an error: " .. tostring(err))
	end
end

-- Loads Profiles.lua as a fresh login with these saved profiles, this character using
-- `selectedName`, and the character's own setup set to "own".
local function Start(profiles, selectedName)
	game = {}
	SetGame("own")
	printed = {}
	ChatProfilesDB = { profiles = profiles or {}, profileByCharacter = { [CHARACTER] = selectedName } }
	local ns = { ChatSettings = FakeChatSettings }
	helpers.LoadAddonFile("ChatProfiles/Profiles.lua", ns)
	Fire("ADDON_LOADED", "ChatProfiles")
	Fire("PLAYER_LOGIN")
	return ns.Profiles, ChatProfilesDB
end

local function SavedProfiles()
	return { Main = Settings("main"), Alt = Settings("alt") }
end

stuck, inCombat = {}, false

-- Login and logout

local Profiles, db = Start(SavedProfiles(), "Main")
for _, category in ipairs(CATEGORIES) do
	Equal(game[category], "main", "login didn't apply the profile's " .. category)
end
Check(Profiles.CanSave(), "Save now was unavailable after a clean login")
game.colors = "changed"
Fire("PLAYER_LOGOUT")
Equal(db.profiles.Main.colors, "changed", "logout didn't save the change")

Profiles, db = Start(nil, nil)
Equal(db.schema, 1, "new saved variables have no schema")
Check(not Profiles.CanSave(), "Save now was available with no profile")
Fire("PLAYER_LOGOUT")
Equal(db.profiles, {}, "logout with no profile saved something")

-- A failed apply

stuck = { tabs = true }
Profiles, db = Start(SavedProfiles(), "Main")
Check(Profiles.LastApplyFailed(), "an apply that left a difference wasn't reported")
Check(printed[1] and printed[1]:find("couldn't be applied"), "a failed login apply printed nothing")
Check(not Profiles.CanSave(), "Save now was available after a failed apply")
Fire("PLAYER_LOGOUT")
Equal(db.profiles.Main.windows.tabs, "main", "logout saved after a failed apply")
stuck = {}
Profiles.Select("Main")
Check(Profiles.CanSave(), "Save now stayed unavailable after a clean apply")

applyError = "a change raised an error"
stuck = { tabs = true }
Start(SavedProfiles(), "Main")
Equal(printed[2], "ChatProfiles: The first error was: a change raised an error", "the first error wasn't printed")
applyError, stuck = nil, {}

-- An apply that raises an error, instead of returning what didn't apply

applyRaises = true
Profiles, db = Start(SavedProfiles(), "Main")
Check(not Profiles.CanSave(), "Save now was available after the login apply raised an error")
Fire("PLAYER_LOGOUT")
Equal(db.profiles.Main.windows.tabs, "main", "logout saved the character's own settings after an error")
applyRaises = false

Profiles, db = Start(SavedProfiles(), "Main")
applyRaises = true
Check(not pcall(Profiles.Select, "Alt"), "the fake apply didn't raise an error")
applyRaises = false
Check(not Profiles.CanSave(), "Save now was available after a switch raised an error")
Fire("PLAYER_LOGOUT")
Equal(db.profiles.Alt.windows.tabs, "alt", "logout saved into the new profile after a switch raised an error")

-- Login in combat

inCombat = true
Profiles, db = Start(SavedProfiles(), "Main")
Equal(game.tabs, "own", "the login apply ran in combat")
Check(Profiles.LoginApplyPending(), "the login apply wasn't held back in combat")
Check(not Profiles.CanSave(), "Save now was available while the login apply waits")
Fire("PLAYER_LOGOUT")
Equal(db.profiles.Main.windows.tabs, "main", "logout saved while the login apply waits")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Equal(game.tabs, "main", "the login apply didn't run when combat ended")
Check(not Profiles.LoginApplyPending(), "the login apply still waits after it ran")
Check(Profiles.CanSave(), "Save now was unavailable after the delayed apply")

inCombat = true
Profiles = Start(SavedProfiles(), "Main")
Profiles.Delete("Main")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Check(not Profiles.LoginApplyPending(), "deleting the profile left the login apply waiting")
Profiles.SaveAsNew("New")
Check(Profiles.CanSave(), "saves stayed off after the waiting profile was deleted")

-- Switching

Profiles, db = Start(SavedProfiles(), "Main")
inCombat = true
local switched, reason = Profiles.Select("Alt")
inCombat = false
Check(switched == nil and reason ~= nil, "a switch in combat wasn't refused")
Equal(Profiles.Selected(), "Main", "a refused switch changed the profile")
Equal(game.tabs, "main", "a refused switch changed the settings")

game.colors = "changed"
Profiles.Select("Alt")
Equal(game.colors, "alt", "switching didn't apply the new profile")
Equal(db.profiles.Main.colors, "main", "switching saved into the old profile")
Profiles.Select("Main")
Equal(game.colors, "main", "the discarded change came back")

local remaining = Profiles.Select(nil)
Equal(remaining, {}, "choosing no profile reported differences")
Check(Profiles.Selected() == nil, "choosing no profile kept the old one")
Equal(game.colors, "main", "choosing no profile changed the settings")
Check(Profiles.Differences() == nil, "a character with no profile had differences")
Check(Profiles.Categories() == nil, "a character with no profile had categories")
Profiles.SetCategoryEnabled("colors", false)
Check(Profiles.Categories() == nil, "a checkbox change without a profile was kept")
game.colors = "changed"
Fire("PLAYER_LOGOUT")
Equal(db.profiles.Main.colors, "main", "logout saved into a profile the character no longer uses")

-- Checkboxes

Profiles, db = Start(SavedProfiles(), "Main")
game.tabs, game.colors = "changed", "changed"
Equal(Texts(Profiles.Differences()), { "tabs differs", "colors differs" }, "wrong differences")
Profiles.SetCategoryEnabled("colors", false)
Equal(db.profiles.Main.categories.colors, true, "a checkbox change was saved before Save now")
Equal(Profiles.Categories().colors, false, "the checkbox change wasn't kept")
Equal(Profiles.UnsavedCategoryChanges(), { colors = false }, "the checkbox change wasn't listed")
Equal(Texts(Profiles.Differences()), { "tabs differs" }, "a category being turned off listed its differences")
Profiles.SetCategoryEnabled("colors", true)
Equal(Profiles.UnsavedCategoryChanges(), {}, "a checkbox set back was still listed")
Equal(Texts(Profiles.Differences()), { "tabs differs", "colors differs" }, "checking a box again hid its differences")

Profiles.SetCategoryEnabled("colors", false)
Profiles.Select("Alt")
Profiles.Select("Main")
Equal(Profiles.Categories().colors, true, "switching away kept the checkbox change")

Profiles.SetCategoryEnabled("colors", false)
Profiles.SaveSelected()
Equal(db.profiles.Main.categories.colors, false, "Save now didn't save the checkbox change")
Check(db.profiles.Main.colors == nil, "a category turned off kept its settings")
Equal(Profiles.UnsavedCategoryChanges(), {}, "a saved checkbox change was still listed")

-- Turned on again: nothing was saved for it, so there's nothing to compare until the next save.
game.tabs, game.colors = "newer", "newer"
Profiles.SetCategoryEnabled("colors", true)
Equal(Profiles.UnsavedCategoryChanges(), { colors = true }, "a category turned on wasn't listed")
Equal(Texts(Profiles.Differences()), { "tabs differs" }, "a category with nothing saved listed differences")
Profiles.SaveSelected()
Equal(db.profiles.Main.colors, "newer", "saving a category turned on didn't save its settings")

Profiles.SetCategoryEnabled("colors", false)
Profiles.Delete("Alt")
Equal(Profiles.UnsavedCategoryChanges(), { colors = false }, "deleting another profile dropped the checkbox change")

for _, category in ipairs(CATEGORIES) do
	Profiles.SetCategoryEnabled(category, false)
end
Check(not Profiles.CanSave(), "Save now was available with no box checked")
Fire("PLAYER_LOGOUT")
Equal(db.profiles.Main.categories.tabs, true, "logout saved with no box checked")

-- Names

Profiles = Start(SavedProfiles(), "Main")
local function Rejects(name, description)
	local saved = Profiles.SaveAsNew(name)
	Check(saved == nil, "SaveAsNew accepted " .. description)
	local imported = Profiles.AddImported(name, Settings("imported"))
	Check(imported == nil, "AddImported accepted " .. description)
end
Rejects("", "an empty name")
Rejects("   ", "a name of only spaces")
Rejects("Main", "a name that's taken")
Rejects("Main   ", "a taken name with spaces after it")
Rejects("Main\194\160", "a taken name with a no-break space after it")
Rejects("\227\128\128Main", "a taken name with an ideographic space before it")
Rejects("a|cffff0000b", "a name with |")
Rejects("a\nb", "a name with a line break")
Rejects(string.rep("a", 51), "a name of 51 characters")

local fiftyAccents = string.rep("\195\169", 50) -- é is two bytes in UTF-8
Equal(Profiles.SaveAsNew(fiftyAccents), fiftyAccents, "a name of 50 two-byte characters was rejected")
Equal(Profiles.SaveAsNew("  Spaced  "), "Spaced", "spaces around a new name weren't trimmed")

Profiles, db = Start(SavedProfiles(), "Main")
db.profileByCharacter["Other-Realm"] = "Main"
Equal(Profiles.Rename("Main", "Main  "), "Main", "renaming to the same name with spaces was rejected")
Equal(Profiles.Names(), { "Alt", "Main" }, "renaming to the same name changed the profiles")
Check(Profiles.Rename("Main", "Alt") == nil, "renaming to a taken name was accepted")
Equal(Profiles.Rename("Main", "Renamed"), "Renamed", "renaming failed")
Equal(Profiles.Names(), { "Alt", "Renamed" }, "renaming didn't move the profile")
Equal(
	db.profileByCharacter,
	{ [CHARACTER] = "Renamed", ["Other-Realm"] = "Renamed" },
	"renaming didn't update every character"
)

Profiles.Delete("Renamed")
Equal(Profiles.Names(), { "Alt" }, "deleting didn't remove the profile")
Equal(db.profileByCharacter, {}, "deleting didn't clear every character")
Equal(game.tabs, "main", "deleting changed the settings")

-- New and Import

Profiles, db = Start(SavedProfiles(), "Main")
Profiles.SetCategoryEnabled("colors", false)
Profiles.SaveAsNew("New")
Equal(Profiles.Selected(), "New", "SaveAsNew didn't switch to the new profile")
Equal(db.profiles.New.categories.colors, false, "SaveAsNew didn't keep the checkboxes")
Equal(db.profiles.Main.categories.colors, true, "SaveAsNew saved the checkbox change into the old profile")

for _, category in ipairs(CATEGORIES) do
	Profiles.SetCategoryEnabled(category, false)
end
Profiles.SaveAsNew("Everything")
Equal(db.profiles.Everything.categories, AllOn(), "SaveAsNew with no box checked didn't save all four")

local beforeImport = helpers.DeepCopy(game)
Profiles.AddImported("Imported", Settings("imported"))
Equal(Profiles.Selected(), "Everything", "importing switched profiles")
Equal(game, beforeImport, "importing changed the settings")

-- The replace popup, for a character that uses no profile

local narrow = { tabs = true, messagesAndChannels = false, fontAndBackground = false, colors = false }
Profiles = Start({ Main = Settings("main"), Alt = Settings("alt"), Narrow = Settings("own", narrow) }, nil)
Check(
	Profiles.WouldLoseUnsavedSettings("Main"),
	"settings saved only in a profile with fewer categories weren't at risk"
)
SetGame("main")
Check(not Profiles.WouldLoseUnsavedSettings("Main"), "settings that match the chosen profile were at risk")
SetGame("alt")
Check(not Profiles.WouldLoseUnsavedSettings("Main"), "settings saved in another profile were at risk")

return helpers.Failures()
