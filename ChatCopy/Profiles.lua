-- Named chat setups that characters follow. Owns ChatCopyDB, the login apply and the logout save.

local addonName, ns = ...
local Chat = ns.Chat

local Profiles = {}
ns.Profiles = Profiles

Profiles.MAX_NAME_LENGTH = 50
local MAX_NAME_LENGTH = Profiles.MAX_NAME_LENGTH

local db

-- Set when an apply leaves differences. A half-applied setup must never be saved into
-- a profile that other characters share, so saves are skipped until an apply succeeds.
local sessionFailed = false

local function CharacterKey()
	return UnitName("player") .. "-" .. GetNormalizedRealmName()
end

local function DefaultInclude()
	return { tabs = true, contents = true, look = true, colors = true }
end

local function CheckNewName(name)
	name = (name or ""):gsub("|", ""):match("^%s*(.-)%s*$")
	if name == "" then
		return nil, "Type a name in the Name box first."
	elseif #name > MAX_NAME_LENGTH then
		return nil, "That name is too long. Names can be up to " .. MAX_NAME_LENGTH .. " characters."
	elseif db.profiles[name] then
		return nil, 'You already have a profile called "' .. name .. '".'
	end
	return name
end

-- Returns what did not apply, and the first error a change raised, if any.
local function Apply(profile)
	local remaining, firstError = Chat.Apply(profile)
	-- After a clean apply, live chat is exactly the profile, so saving is safe again.
	sessionFailed = #remaining > 0
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

-- Returns the name and profile this character follows, or nil.
function Profiles.Selected()
	local name = db.characters[CharacterKey()]
	if name and db.profiles[name] then
		return name, db.profiles[name]
	end
end

function Profiles.HasFailed()
	return sessionFailed
end

-- Returns what differs between live chat and the selected profile, and any tab names
-- that appear twice. Returns nil if this character follows no profile.
function Profiles.Status()
	local _, profile = Profiles.Selected()
	if not profile then
		return nil
	end
	local live = Chat.Read(profile.include)
	return Chat.Diff(live, profile), live.duplicates
end

-- Saves live chat into the selected profile. Runs at logout, on Save Now, and before
-- switching profiles.
function Profiles.SaveSelected()
	local _, profile = Profiles.Selected()
	if not profile or sessionFailed then
		return false
	end
	local live = Chat.Read(profile.include)
	profile.windows = live.windows
	profile.colors = live.colors
	return true
end

-- Saves into the current profile, then applies the new one. Pass nil to follow no profile.
-- Returns what did not apply.
function Profiles.Select(name)
	Profiles.SaveSelected()
	db.characters[CharacterKey()] = name
	if not name then
		return {}
	end
	return Apply(db.profiles[name])
end

-- Makes live chat a new profile and follows it. The previous profile is left as it was.
function Profiles.SaveAsNew(name)
	local newName, reason = CheckNewName(name)
	if not newName then
		return nil, reason
	end
	local include = DefaultInclude()
	local live = Chat.Read(include)
	db.profiles[newName] = { include = include, windows = live.windows, colors = live.colors }
	db.characters[CharacterKey()] = newName
	-- The new profile is exactly the live setup, so nothing half-applied is left to protect.
	sessionFailed = false
	return newName
end

-- Adds an imported profile. It is not applied until a character selects it.
function Profiles.Add(name, profile)
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
	for character, followed in pairs(db.characters) do
		if followed == oldName then
			db.characters[character] = newName
		end
	end
	return newName
end

-- Deletes a profile. Characters that followed it keep their chat and follow nothing.
function Profiles.Delete(name)
	db.profiles[name] = nil
	for character, followed in pairs(db.characters) do
		if followed == name then
			db.characters[character] = nil
		end
	end
end

function Profiles.SetInclude(category, enabled)
	local _, profile = Profiles.Selected()
	if profile then
		profile.include[category] = enabled
	end
end

local function LoadSavedVariables()
	-- Assign the global itself: the client only writes out what ChatCopyDB points to.
	ChatCopyDB = ChatCopyDB or {}
	db = ChatCopyDB
	db.schema = db.schema or 1
	db.profiles = db.profiles or {}
	db.characters = db.characters or {}
end

local function ApplyAtLogin()
	local name, profile = Profiles.Selected()
	if not profile then
		return
	end
	local remaining, firstError = Apply(profile)
	if #remaining > 0 then
		print(
			'ChatCopy: Some settings from "'
				.. name
				.. "\" couldn't be applied, so changes won't be saved until you reload or log in again."
				.. " Type /chatcopy for details."
		)
		if firstError then
			print("ChatCopy: The first error was: " .. tostring(firstError))
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, loadedAddon)
	if event == "ADDON_LOADED" then
		if loadedAddon == addonName then
			LoadSavedVariables()
			self:UnregisterEvent(event)
		end
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent(event)
		-- One frame later, so other addons' login handlers, such as chat history restore, run first.
		C_Timer.After(0, ApplyAtLogin)
	elseif event == "PLAYER_LOGOUT" then
		Profiles.SaveSelected()
	end
end)
