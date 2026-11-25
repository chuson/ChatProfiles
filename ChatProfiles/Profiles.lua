-- Named sets of chat settings that characters use. Owns ChatProfilesDB, the login apply and the logout save.

local addonName, ns = ...
local ChatSettings = ns.ChatSettings

local Profiles = {}
ns.Profiles = Profiles

Profiles.MAX_PROFILE_NAME_LENGTH = 50
local MAX_PROFILE_NAME_LENGTH = Profiles.MAX_PROFILE_NAME_LENGTH

local db

-- Set when an apply leaves differences. A half-applied setup must never be saved into
-- a profile that other characters share, so saves are skipped until an apply succeeds.
local lastApplyFailed = false

local function CharacterKey()
	return UnitName("player") .. "-" .. GetNormalizedRealmName()
end

-- A new table each call, since profiles edit theirs in place.
local function DefaultCategories()
	return { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true }
end

local function CheckNewName(name)
	-- Strip "|" (escape codes) before trimming, so "a |" doesn't leave a trailing space.
	name = (name or ""):gsub("|", ""):match("^%s*(.-)%s*$")
	if name == "" then
		return nil, "Type a name in the Name box first."
	elseif #name > MAX_PROFILE_NAME_LENGTH then
		return nil, "That name is too long. Names can be up to " .. MAX_PROFILE_NAME_LENGTH .. " characters."
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

-- Saves the live settings into the selected profile. Runs at logout, on Save now, and before
-- switching profiles.
--
-- Saves even when nothing seems to differ: a category that was just turned on has no
-- saved data to compare against yet. Categories that are turned off are dropped.
function Profiles.SaveSelected()
	local _, profile = Profiles.Selected()
	if not profile or lastApplyFailed then
		return false
	end
	local live = ChatSettings.Read(profile.categories)
	profile.windows = live.windows
	profile.colors = live.colors
	return true
end

-- Saves into the current profile, then applies the new one. Pass nil to use no profile.
-- Returns what did not apply.
function Profiles.Select(name)
	-- Changes since the last save belong to the old profile, so save before switching.
	Profiles.SaveSelected()
	db.profileByCharacter[CharacterKey()] = name
	if not name then
		return {}
	end
	return Apply(db.profiles[name])
end

-- Makes the live settings a new profile and uses it. The previous profile is left as it was.
function Profiles.SaveAsNew(name)
	local newName, reason = CheckNewName(name)
	if not newName then
		return nil, reason
	end
	local categories = DefaultCategories()
	local live = ChatSettings.Read(categories)
	db.profiles[newName] = { categories = categories, windows = live.windows, colors = live.colors }
	db.profileByCharacter[CharacterKey()] = newName
	-- The new profile is exactly the live setup, so nothing half-applied is left to protect.
	lastApplyFailed = false
	return newName
end

-- Adds an imported profile. It is not applied until a character selects it.
function Profiles.AddImported(name, profile)
	local newName, reason = CheckNewName(name)
	if not newName then
		return nil, reason
	end
	db.profiles[newName] = profile
	return newName
end

function Profiles.Rename(oldName, name)
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

function Profiles.SetCategoryEnabled(category, enabled)
	local _, profile = Profiles.Selected()
	if profile then
		profile.categories[category] = enabled
	end
end

local function LoadSavedVariables()
	-- Assign the global, not just `db`: at logout the client saves whatever ChatProfilesDB points to.
	ChatProfilesDB = ChatProfilesDB or {}
	db = ChatProfilesDB
	db.schema = db.schema or 1
	db.profiles = db.profiles or {}
	db.profileByCharacter = db.profileByCharacter or {}
end

local function ApplyAtLogin()
	local name, profile = Profiles.Selected()
	if not profile then
		return
	end
	local remaining, firstError = Apply(profile)
	if #remaining > 0 then
		print(
			'Chat Profiles: Some settings from "'
				.. name
				.. "\" couldn't be applied, so changes won't be saved until you reload or log in again."
				.. " Type /chatprofiles for details."
		)
		if firstError then
			print("Chat Profiles: The first error was: " .. tostring(firstError))
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, loadedAddon)
	if event == "ADDON_LOADED" then
		-- Fires once per addon. Saved variables are ready when it fires for ours.
		if loadedAddon == addonName then
			LoadSavedVariables()
			self:UnregisterEvent(event)
		end
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent(event)
		-- On a fresh login, chat settings are still arriving from the server around ADDON_LOADED
		-- and would overwrite anything applied then. By PLAYER_LOGIN they're in (measured; see
		-- design doc section 6). Deferring with After(0) lets other addons' login code run first.
		C_Timer.After(0, ApplyAtLogin)
	elseif event == "PLAYER_LOGOUT" then
		-- Also fires on /reload, and chat settings can still be read here.
		Profiles.SaveSelected()
	end
end)
