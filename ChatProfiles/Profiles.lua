-- Profiles are named sets of chat settings that characters use. This file owns ChatProfilesDB,
-- the login apply and the logout save.

local addonName, ns = ...
local ChatSettings = ns.ChatSettings

local Profiles = {}
ns.Profiles = Profiles

Profiles.MAX_PROFILE_NAME_LENGTH = 50

local db -- ChatProfilesDB, set when this addon's saved variables load

-- Set when an apply leaves differences. Other characters share the profile, so a half-applied
-- setup must never overwrite it. Saves are skipped until an apply succeeds.
local lastApplyFailed = false

-- Set while the login apply waits for combat to end. Until then the live settings are this
-- character's, not the profile's, so saving them would overwrite the profile.
local loginApplyPending = false

-- Checkbox changes for the selected profile, waiting for the next save like any other change.
-- Kept for this session only, so a switch, /reload or logout without a save drops them.
local pendingCategories

local function AllCategoriesOn()
	return { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true }
end

local function CharacterKey()
	return UnitName("player") .. "-" .. GetNormalizedRealmName()
end

-- %s is ASCII-only, so U+00A0 (no-break space) and U+3000 (ideographic space, typed by CJK
-- keyboards) are trimmed separately.
local function TrimSpaces(text)
	local before
	repeat
		before = text
		text = text:match("^%s*(.-)%s*$")
		text = text:gsub("^\194\160", ""):gsub("\194\160$", "")
		text = text:gsub("^\227\128\128", ""):gsub("\227\128\128$", "")
	until text == before
	return text
end

local function CheckNewName(name)
	name = TrimSpaces(name or "")
	-- strlenutf8 counts characters, matching the popup's SetMaxLetters. # would count bytes.
	local characters = strlenutf8(name)
	local limit = Profiles.MAX_PROFILE_NAME_LENGTH
	if characters == 0 then
		return nil, "Give the profile a name first."
	elseif name:find("[|%c]") then
		-- "|" starts the client's escape sequences (|c, |H, |T). The message writes "||" to show one "|".
		return nil, "Names can't contain || or line breaks."
	elseif characters > limit then
		return nil, "That name is too long. Names can be up to " .. limit .. " characters."
	elseif db.profiles[name] then
		return nil, 'You already have a profile called "' .. name .. '".'
	end
	return name
end

-- Returns what did not apply, and the first error a change raised, if any.
local function Apply(profile)
	local remaining, firstError = ChatSettings.Apply(profile)
	-- After a clean apply, the live settings match the profile exactly, so saving is safe again.
	lastApplyFailed = #remaining > 0
	return remaining, firstError
end

function Profiles.Names()
	local names = {}
	for name in pairs(db.profiles) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Returns the name and profile this character uses, or nil.
function Profiles.Selected()
	local name = db.profileByCharacter[CharacterKey()]
	if name and db.profiles[name] then
		return name, db.profiles[name]
	end
end

function Profiles.LastApplyFailed()
	return lastApplyFailed
end

-- Returns what differs between the live settings and the selected profile, and any tab names
-- that appear twice. Returns nil if this character uses no profile.
function Profiles.Differences()
	local _, profile = Profiles.Selected()
	if not profile then
		return nil
	end
	-- Compares only what the next save keeps: categories that are saved and still checked.
	local checked, compared = Profiles.Categories(), {}
	for category, on in pairs(profile.categories) do
		compared[category] = on and checked[category]
	end
	local live = ChatSettings.Read(compared)
	return ChatSettings.Diff(live, profile, compared), live.duplicateTabNames
end

function Profiles.HasCategoryOn(categories)
	for _, on in pairs(categories) do
		if on then
			return true
		end
	end
	return false
end

-- Returns the selected profile's categories as the checkboxes show them, including changes that
-- aren't saved yet, or nil if this character uses no profile.
function Profiles.Categories()
	local _, profile = Profiles.Selected()
	return profile and (pendingCategories or profile.categories)
end

-- Returns the categories whose checkbox differs from the saved profile, mapped to the new value.
function Profiles.UnsavedCategoryChanges()
	local _, profile = Profiles.Selected()
	local changes = {}
	if profile and pendingCategories then
		for category, on in pairs(pendingCategories) do
			if on ~= (profile.categories[category] == true) then
				changes[category] = on
			end
		end
	end
	return changes
end

function Profiles.SetCategoryEnabled(category, enabled)
	local _, profile = Profiles.Selected()
	if not profile then
		return
	end
	pendingCategories = pendingCategories or CopyTable(profile.categories)
	pendingCategories[category] = enabled
end

-- Returns true if SaveSelected would save now. With every category off nothing is saved, so the
-- profile keeps its last saved selection.
function Profiles.CanSave()
	local categories = Profiles.Categories()
	return categories ~= nil and Profiles.HasCategoryOn(categories) and not lastApplyFailed and not loginApplyPending
end

-- Saves the live settings and any checkbox changes into the selected profile. Runs at logout and
-- on Save now.
--
-- Saves even when nothing seems to differ. A category that was just turned on has no saved
-- data yet, so the comparison can't see its changes. Categories that are turned off are dropped.
function Profiles.SaveSelected()
	if not Profiles.CanSave() then
		return
	end
	local _, profile = Profiles.Selected()
	local categories = pendingCategories or profile.categories
	local live = ChatSettings.Read(categories)
	profile.categories = categories
	profile.windows = live.windows
	profile.colors = live.colors
	pendingCategories = nil
end

-- Returns true if choosing profile `name` would replace settings that aren't saved anywhere:
-- the live settings differ from that profile, and from every profile that saves at least the
-- same categories.
function Profiles.WouldLoseUnsavedSettings(name)
	local target = db.profiles[name]
	local function MatchesLive(profile)
		return #ChatSettings.Diff(ChatSettings.Read(profile.categories), profile) == 0
	end
	local function SavesAllOf(profile, categories)
		for category, on in pairs(categories) do
			if on and not profile.categories[category] then
				return false
			end
		end
		return true
	end

	if MatchesLive(target) then
		return false
	end
	for _, profile in pairs(db.profiles) do
		if SavesAllOf(profile, target.categories) and MatchesLive(profile) then
			return false
		end
	end
	return true
end

-- Applies a profile. Pass nil to use no profile. Returns what did not apply, or nil and a reason
-- if the switch can't happen now.
--
-- Unsaved changes are discarded, not saved into the old profile: switching away with Save now
-- available means the player chose not to keep them, and the old profile stays as last saved.
function Profiles.Select(name)
	-- The game blocks some chat changes in combat, and a blocked change fails without an error.
	if InCombatLockdown() then
		return nil, "You can't switch profiles in combat."
	end
	pendingCategories = nil
	db.profileByCharacter[CharacterKey()] = name
	if not name then
		return {}
	end
	return Apply(db.profiles[name])
end

-- Saves the live settings as a new profile and switches this character to it. The previous
-- profile is left unchanged.
function Profiles.SaveAsNew(name)
	local newName, reason = CheckNewName(name)
	if not newName then
		return nil, reason
	end
	-- Start from the checkboxes as they are, so a category turned off on purpose stays off, or all
	-- four if none are checked.
	local current = Profiles.Categories()
	local categories = (current and Profiles.HasCategoryOn(current)) and CopyTable(current) or AllCategoriesOn()
	local live = ChatSettings.Read(categories)
	db.profiles[newName] = { categories = categories, windows = live.windows, colors = live.colors }
	db.profileByCharacter[CharacterKey()] = newName
	pendingCategories = nil
	-- The new profile is exactly the live setup, so nothing half-applied is left to protect.
	lastApplyFailed = false
	return newName
end

-- Adds an imported profile. It isn't applied until the player selects it on a character.
function Profiles.AddImported(name, profile)
	local newName, reason = CheckNewName(name)
	if not newName then
		return nil, reason
	end
	db.profiles[newName] = profile
	return newName
end

function Profiles.Rename(oldName, name)
	-- The name check below would reject the unchanged name as one that's already taken. Spaces
	-- around a name are trimmed, so "Main " is still Main.
	if TrimSpaces(name or "") == oldName then
		return oldName
	end
	local newName, reason = CheckNewName(name)
	if not newName then
		return nil, reason
	end
	db.profiles[newName], db.profiles[oldName] = db.profiles[oldName], nil
	for character, profileName in pairs(db.profileByCharacter) do
		if profileName == oldName then
			db.profileByCharacter[character] = newName
		end
	end
	return newName
end

-- Deletes a profile. Characters that used it keep their chat settings and use no profile.
function Profiles.Delete(name)
	if name == Profiles.Selected() then
		pendingCategories = nil
	end
	db.profiles[name] = nil
	for character, profileName in pairs(db.profileByCharacter) do
		if profileName == name then
			db.profileByCharacter[character] = nil
		end
	end
end

local function LoadSavedVariables()
	-- Assign the global, not just `db`: at logout the client saves whatever table the global holds.
	ChatProfilesDB = ChatProfilesDB or {}
	db = ChatProfilesDB
	db.schema = db.schema or 1
	db.profiles = db.profiles or {}
	db.profileByCharacter = db.profileByCharacter or {}
end

local events = CreateFrame("Frame")

local function ApplyAtLogin()
	local name, profile = Profiles.Selected()
	if not profile then
		return
	end
	-- A /reload can happen mid-fight, and the game blocks some chat changes in combat.
	if InCombatLockdown() then
		loginApplyPending = true
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	loginApplyPending = false
	local remaining, firstError = Apply(profile)
	if #remaining > 0 then
		print(
			'ChatProfiles: Some settings from "'
				.. name
				.. "\" couldn't be applied, so changes won't be saved until you reload or log in again."
				.. " Type /chatprofiles for details."
		)
		if firstError then
			print("ChatProfiles: The first error was: " .. tostring(firstError))
		end
	end
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, loadedAddon)
	if event == "ADDON_LOADED" then
		-- Saved variables are loaded by the time this fires for our own addon.
		if loadedAddon == addonName then
			LoadSavedVariables()
			self:UnregisterEvent(event)
		end
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent(event)
		-- On a fresh login, chat settings are still arriving from the server around ADDON_LOADED
		-- and would overwrite anything applied then. They have all arrived by PLAYER_LOGIN, as
		-- measured for open question 1 in the design doc. Deferring with After(0) lets other addons'
		-- login code run first.
		C_Timer.After(0, ApplyAtLogin)
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Combat has ended after a login apply was put off.
		self:UnregisterEvent(event)
		ApplyAtLogin()
	elseif event == "PLAYER_LOGOUT" then
		-- This also fires on /reload. Chat settings can still be read at this point.
		Profiles.SaveSelected()
	end
end)
