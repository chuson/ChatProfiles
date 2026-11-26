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
	local live = ChatSettings.Read(profile.categories)
	return ChatSettings.Diff(live, profile), live.duplicateTabNames
end

function Profiles.HasCategoryOn(profile)
	for _, on in pairs(profile.categories) do
		if on then
			return true
		end
	end
	return false
end

-- Saves the live settings into the selected profile. Runs at logout, on Save now, and before
-- switching profiles.
--
-- Saves even when nothing seems to differ. A category that was just turned on has no saved
-- data yet, so the comparison can't see its changes. Categories that are turned off are dropped,
-- so with every category off nothing is saved, rather than emptying the profile.
function Profiles.SaveSelected()
	local _, profile = Profiles.Selected()
	if not profile or lastApplyFailed or loginApplyPending or not Profiles.HasCategoryOn(profile) then
		return
	end
	local live = ChatSettings.Read(profile.categories)
	profile.windows = live.windows
	profile.colors = live.colors
end

function Profiles.SetCategoryEnabled(category, enabled)
	local _, profile = Profiles.Selected()
	if profile then
		profile.categories[category] = enabled
	end
end

-- Saves into the selected profile, then applies the new one. Pass nil to use no profile.
-- Returns what did not apply, or nil and a reason if the switch can't happen now.
function Profiles.Select(name)
	-- The game blocks some chat changes in combat, and a blocked change fails without an error.
	if InCombatLockdown() then
		return nil, "You can't switch profiles in combat."
	end
	-- Changes since the last save belong to the old profile, so save before switching.
	Profiles.SaveSelected()
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
	-- Start from the selected profile's categories, so one that was turned off on purpose stays off.
	local _, selected = Profiles.Selected()
	local categories = { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true }
	if selected and Profiles.HasCategoryOn(selected) then
		for category, enabled in pairs(selected.categories) do
			categories[category] = enabled
		end
	end
	local live = ChatSettings.Read(categories)
	db.profiles[newName] = { categories = categories, windows = live.windows, colors = live.colors }
	db.profileByCharacter[CharacterKey()] = newName
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
	-- The name check below would reject the unchanged name as one that's already taken.
	if name == oldName then
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
