-- Reads the live chat setup, compares it with a profile, and applies a profile.
-- Nothing here prints or touches saved data: callers decide what to do with the results.

local _, ns = ...

local Chat = {}
ns.Chat = Chat

local GENERAL = 1
local COMBAT_LOG = 2
local MAX_WINDOWS = Constants.ChatFrameConstants.MaxChatWindows

-- The client stores colors as 0-255, so values read back are rounded.
local function Near(x, y)
	return math.abs(x - y) < 0.01
end

local function SameColor(have, want)
	return Near(have.r, want.r) and Near(have.g, want.g) and Near(have.b, want.b)
end

local function FirstCustomId()
	return C_ChatInfo.GetNumReservedChatWindows() + 1
end

local function IsCustomKey(key)
	return key:sub(1, 5) == "name:"
end

-- Most chat types have a display name among the client's global strings, such as SAY = "Say".
local function ChatTypeName(chatType)
	local name = _G[chatType]
	return type(name) == "string" and name or chatType
end

-- Built-in zone channels have localized names, so they are matched by ID.
-- Custom channels have no ID and are matched by name.
local function ChannelKey(channel)
	if channel.zoneID > 0 then
		return channel.zoneID
	end
	return channel.name:lower()
end

local function ChannelName(channel)
	if channel.zoneID > 0 then
		return C_ChatInfo.GetChannelShortcutForChannelID(channel.zoneID) or channel.name
	end
	return channel.name
end

local function ReadChannels(id)
	local channels = {}
	local values = { GetChatWindowChannels(id) }
	for i = 1, #values, 2 do
		table.insert(channels, { name = values[i], zoneID = values[i + 1] or 0 })
	end
	table.sort(channels, function(a, b)
		return a.name < b.name
	end)
	return channels
end

local function ReadGroups(id)
	local groups = { GetChatWindowMessages(id) }
	table.sort(groups)
	return groups
end

local function ReadColors()
	local colors = {}
	for chatType, info in pairs(ChatTypeInfo) do
		if info.r then
			colors[chatType] = { r = info.r, g = info.g, b = info.b, classColor = info.colorNameByClass }
		end
	end
	return colors
end

-- Returns the live setup in the same shape as a profile, leaving out categories that
-- `include` turns off. Tabs that share a name are listed in `duplicates` and only the
-- first is used. `ids` maps each window's key to its chat frame number; it is kept apart
-- from `windows` because those are saved into profiles and frame numbers differ per character.
function Chat.Read(include)
	local setup = { windows = {}, ids = {}, duplicates = {} }
	local dockOrder = {}
	local seen = {}
	local firstCustom = FirstCustomId()

	for id = 1, MAX_WINDOWS do
		local name, size, r, g, b, a, shown, locked, docked = GetChatWindowInfo(id)
		local tracked = id == GENERAL or id == COMBAT_LOG or (id >= firstCustom and name and name ~= "")

		-- A docked tab that is not selected reports shown = false, so check docked too.
		if tracked and (shown or docked) then
			local key = id < firstCustom and ("id:" .. id) or ("name:" .. name)
			if seen[key] then
				table.insert(setup.duplicates, name)
			else
				seen[key] = true
				setup.ids[key] = id
				local window = { key = key, name = name }
				if include.look then
					window.size, window.r, window.g, window.b, window.a = size, r, g, b, a
					window.locked = locked and true or false
				end
				if include.contents and id ~= COMBAT_LOG then
					window.groups = ReadGroups(id)
					window.channels = ReadChannels(id)
				end
				dockOrder[window] = docked or (MAX_WINDOWS + id)
				table.insert(setup.windows, window)
			end
		end
	end

	-- Dock order, so that missing tabs are created in the same order on another character.
	table.sort(setup.windows, function(x, y)
		return dockOrder[x] < dockOrder[y]
	end)

	if include.colors then
		setup.colors = ReadColors()
	end
	return setup
end

-- Returns what is in `want` but not `have`, and what is in `have` but not `want`.
local function SetDifference(have, want, keyOf)
	local haveKeys, wantKeys = {}, {}
	for _, item in ipairs(have) do
		haveKeys[keyOf(item)] = true
	end
	for _, item in ipairs(want) do
		wantKeys[keyOf(item)] = true
	end

	local missing, extra = {}, {}
	for _, item in ipairs(want) do
		if not haveKeys[keyOf(item)] then
			table.insert(missing, item)
		end
	end
	for _, item in ipairs(have) do
		if not wantKeys[keyOf(item)] then
			table.insert(extra, item)
		end
	end
	return missing, extra
end

-- A setting the profile does not have (nil) is left alone. A font size of 0 means
-- the profile's character never set one, so it is left alone too.
local LOOK = {
	{
		label = "different font size",
		differs = function(have, want)
			return want.size ~= nil and want.size > 0 and have.size ~= want.size
		end,
		apply = function(frame, want)
			FCF_SetChatWindowFontSize(nil, frame, want.size)
		end,
	},
	{
		label = "different background color",
		differs = function(have, want)
			return want.r ~= nil and not SameColor(have, want)
		end,
		apply = function(frame, want)
			FCF_SetWindowColor(frame, want.r, want.g, want.b)
		end,
	},
	{
		label = "different background opacity",
		differs = function(have, want)
			return want.a ~= nil and not Near(have.a, want.a)
		end,
		apply = function(frame, want)
			FCF_SetWindowAlpha(frame, want.a)
		end,
	},
	{
		label = "locked differently",
		differs = function(have, want)
			return want.locked ~= nil and have.locked ~= want.locked
		end,
		apply = function(frame, want)
			FCF_SetLocked(frame, want.locked)
		end,
	},
}

local function DiffWindow(frame, have, want, include, add)
	if include.look then
		for _, setting in ipairs(LOOK) do
			if setting.differs(have, want) then
				add(have.name .. ": " .. setting.label, function()
					setting.apply(frame, want)
				end)
			end
		end
	end

	if not include.contents or want.key == "id:" .. COMBAT_LOG then
		return
	end

	if want.groups and have.groups then
		local missing, extra = SetDifference(have.groups, want.groups, function(group)
			return group
		end)
		for _, group in ipairs(missing) do
			add(have.name .. ": no " .. ChatTypeName(group) .. " messages", function()
				frame:AddMessageGroup(group)
			end)
		end
		for _, group in ipairs(extra) do
			add(have.name .. ": extra " .. ChatTypeName(group) .. " messages", function()
				frame:RemoveMessageGroup(group)
			end)
		end
	end

	if want.channels and have.channels then
		local missing, extra = SetDifference(have.channels, want.channels, ChannelKey)
		for _, channel in ipairs(missing) do
			local name = ChannelName(channel)
			add(have.name .. ": no " .. name .. " channel", function()
				frame:AddChannel(name)
			end)
		end
		for _, channel in ipairs(extra) do
			add(have.name .. ": extra " .. channel.name .. " channel", function()
				frame:RemoveChannel(channel.name)
			end)
		end
	end
end

local function DiffColors(have, want, add)
	local chatTypes = {}
	for chatType in pairs(want) do
		table.insert(chatTypes, chatType)
	end
	table.sort(chatTypes)

	for _, chatType in ipairs(chatTypes) do
		local current, wanted = have[chatType], want[chatType]
		if current then
			if not SameColor(current, wanted) then
				add("Different color for " .. ChatTypeName(chatType), function()
					ChangeChatColor(chatType, wanted.r, wanted.g, wanted.b)
				end)
			end
			-- Only chat types that support class-colored names report the flag.
			if current.classColor ~= nil and wanted.classColor ~= nil and current.classColor ~= wanted.classColor then
				add("Different name coloring for " .. ChatTypeName(chatType), function()
					SetChatColorNameByClass(chatType, wanted.classColor)
				end)
			end
		end
	end
end

-- Returns a list of { text, run, changesTabs }, one per setting that differs. `text` says
-- how live chat differs from the profile, and `run` makes it match. An empty list means
-- the live setup matches the profile.
function Chat.Diff(live, profile)
	local include = profile.include
	local changes = {}
	local function Add(text, run, changesTabs)
		table.insert(changes, { text = text, run = run, changesTabs = changesTabs or false })
	end

	local wanted = {}
	for _, want in ipairs(profile.windows) do
		wanted[want.key] = true
	end

	-- Closes come before creates, so a full set of tabs frees a slot before a new one is needed.
	if include.tabs then
		for _, have in ipairs(live.windows) do
			if IsCustomKey(have.key) and not wanted[have.key] then
				local frame = _G["ChatFrame" .. live.ids[have.key]]
				Add('Extra tab "' .. have.name .. '"', function()
					FCF_Close(frame)
				end, true)
			end
		end
	end

	local liveByKey = {}
	for _, have in ipairs(live.windows) do
		liveByKey[have.key] = have
	end

	for _, want in ipairs(profile.windows) do
		local have = liveByKey[want.key]
		if have then
			DiffWindow(_G["ChatFrame" .. live.ids[want.key]], have, want, include, Add)
		elseif include.tabs and IsCustomKey(want.key) then
			Add('Missing tab "' .. want.name .. '"', function()
				FCF_OpenNewWindow(want.name, true)
			end, true)
		end
	end

	if include.colors and profile.colors and live.colors then
		DiffColors(live.colors, profile.colors, Add)
	end

	return changes
end

-- Applies a profile and returns what still differs afterward (empty means success), plus
-- the first error a change raised, if any. Each change runs on its own, so one failing call
-- does not stop the rest, and a call that errors or silently does nothing shows up the same
-- way: in the returned list.
function Chat.Apply(profile)
	local firstError
	local function Run(runTabChanges)
		for _, change in ipairs(Chat.Diff(Chat.Read(profile.include), profile)) do
			if change.changesTabs == runTabChanges then
				local ok, err = pcall(change.run)
				if not ok then
					firstError = firstError or err
				end
			end
		end
	end

	-- First open and close tabs, then diff again, so the rest also covers whatever a new tab starts with.
	Run(true)
	Run(false)
	return Chat.Diff(Chat.Read(profile.include), profile), firstError
end
