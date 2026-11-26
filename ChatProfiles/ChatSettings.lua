-- Reads the live chat settings, compares them with a profile, and applies a profile.
-- Nothing here prints or touches saved data: callers decide what to do with the results.

local _, ns = ...

local ChatSettings = {}
ns.ChatSettings = ChatSettings

-- General and Combat Log are always windows 1 and 2, so they're keyed by window number ("window:1").
-- Tabs the player creates go into whichever window is free, so they're keyed by name ("name:Trade").
local GENERAL_WINDOW = 1
local COMBAT_LOG_WINDOW = 2
local MAX_WINDOWS = Constants.ChatFrameConstants.MaxChatWindows

local function ReadChannels(windowNumber)
	local channels = {}
	-- Returns name1, id1, name2, id2, ...
	local values = { GetChatWindowChannels(windowNumber) }
	for i = 1, #values, 2 do
		table.insert(channels, { name = values[i], zoneChannelID = values[i + 1] or 0 })
	end
	table.sort(channels, function(a, b)
		return a.name < b.name
	end)
	return channels
end

local function ReadWindow(windowNumber, key, categories)
	local name, fontSize, r, g, b, a, _, locked = GetChatWindowInfo(windowNumber)
	local window = { key = key, name = name }
	if categories.tabs then
		window.locked = locked and true or false -- the API returns 1 or nil
	end
	if categories.fontAndBackground then
		window.fontSize, window.r, window.g, window.b, window.a = fontSize, r, g, b, a
	end
	-- The combat log uses its own filters, not message groups. Both lists are sorted, so an
	-- unchanged setup saves and exports the same way every time.
	if categories.messagesAndChannels and windowNumber ~= COMBAT_LOG_WINDOW then
		window.messageGroups = { GetChatWindowMessages(windowNumber) }
		table.sort(window.messageGroups)
		window.channels = ReadChannels(windowNumber)
	end
	return window
end

-- ChatTypeInfo is an empty proxy once chat loads (see ChatFrameUtil.ImportAllListsToHash).
-- The entries live in its metatable's __index, so pairs(ChatTypeInfo) finds nothing.
local function ReadColors()
	local metatable = getmetatable(ChatTypeInfo)
	local chatTypes = metatable and type(metatable.__index) == "table" and metatable.__index or ChatTypeInfo
	local colors = {}
	for chatType, info in pairs(chatTypes) do
		if info.r then
			colors[chatType] = { r = info.r, g = info.g, b = info.b, classColoredNames = info.colorNameByClass }
		end
	end
	return colors
end

-- Returns the live settings in the same shape as a profile, leaving out categories that are
-- turned off. If two tabs share a name, only the first is used and the name is listed in
-- `duplicateTabNames`. `windowNumbers` maps each key to its window number. Window numbers
-- differ between characters, so they're kept out of `windows`, which is the part that gets saved.
function ChatSettings.Read(categories)
	local live = { windows = {}, windowNumbers = {}, duplicateTabNames = {} }
	local dockOrder = {}
	-- The client reserves the first few windows (window 3 is voice transcription). We only touch 1 and 2.
	local firstCustomWindow = C_ChatInfo.GetNumReservedChatWindows() + 1

	for windowNumber = 1, MAX_WINDOWS do
		local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(windowNumber)
		local isCustom = windowNumber >= firstCustomWindow
		local tracked = windowNumber == GENERAL_WINDOW
			or windowNumber == COMBAT_LOG_WINDOW
			or (isCustom and name and name ~= "")

		-- A window keeps its name after its tab is closed, so check shown or docked. A docked
		-- tab that isn't the selected one reports shown = false.
		if tracked and (shown or docked) then
			local key = isCustom and ("name:" .. name) or ("window:" .. windowNumber)
			if live.windowNumbers[key] then
				table.insert(live.duplicateTabNames, name)
			else
				live.windowNumbers[key] = windowNumber
				local window = ReadWindow(windowNumber, key, categories)
				-- `docked` is the position in the dock, or nil. Undocked windows sort last.
				dockOrder[window] = docked or (MAX_WINDOWS + windowNumber)
				table.insert(live.windows, window)
			end
		end
	end

	-- New tabs are added to the end of the dock, so creating them in dock order reproduces
	-- the layout. Tabs that already exist can't be moved.
	table.sort(live.windows, function(x, y)
		return dockOrder[x] < dockOrder[y]
	end)

	if categories.colors then
		live.colors = ReadColors()
	end
	return live
end

-- Most chat types have a display name in the global strings, e.g. SAY = "Say".
local function ChatTypeName(chatType)
	local name = _G[chatType]
	return type(name) == "string" and name or chatType
end

-- Zone channels (General, Trade) have localized names, so they're matched by ID. Custom
-- channels are matched by name, case-insensitively: the game treats "cpTEST" and "Cptest" as
-- one channel and reports it in the case it was joined with. Saved names keep their case.
local function ChannelKey(channel)
	if channel.zoneChannelID > 0 then
		return channel.zoneChannelID
	end
	return channel.name:lower()
end

-- The profile may come from a client in another language, so ask this client what the zone channel is called.
local function ClientChannelName(channel)
	if channel.zoneChannelID > 0 then
		return C_ChatInfo.GetChannelShortcutForChannelID(channel.zoneChannelID) or channel.name
	end
	return channel.name
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

-- The client stores colors as 0-255, so values read back are rounded.
local function NearlyEqual(x, y)
	return math.abs(x - y) < 0.01
end

local function SameColor(have, want)
	return NearlyEqual(have.r, want.r) and NearlyEqual(have.g, want.g) and NearlyEqual(have.b, want.b)
end

-- A setting the profile doesn't have (nil) is left alone. So is font size 0, which means it
-- was never set.
local function DiffWindow(frame, have, want, categories, addDifference)
	local function Add(text, apply)
		addDifference(have.name .. ": " .. text, apply)
	end

	if categories.tabs and want.locked ~= nil and have.locked ~= want.locked then
		Add("locked differently", function()
			FCF_SetLocked(frame, want.locked)
		end)
	end

	if categories.fontAndBackground then
		if want.fontSize ~= nil and want.fontSize > 0 and have.fontSize ~= want.fontSize then
			Add("different font size", function()
				-- The first argument is Blizzard's menu button; it's only read when the size is nil.
				FCF_SetChatWindowFontSize(nil, frame, want.fontSize)
			end)
		end
		if want.r ~= nil and not SameColor(have, want) then
			Add("different background color", function()
				FCF_SetWindowColor(frame, want.r, want.g, want.b)
			end)
		end
		if want.a ~= nil and not NearlyEqual(have.a, want.a) then
			Add("different background opacity", function()
				FCF_SetWindowAlpha(frame, want.a)
			end)
		end
	end

	-- Either side may have no message groups or channels: the combat log never does, and
	-- neither does a profile saved while this category was off.
	if categories.messagesAndChannels and want.messageGroups and have.messageGroups then
		local missing, extra = SetDifference(have.messageGroups, want.messageGroups, function(group)
			return group
		end)
		for _, group in ipairs(missing) do
			Add("doesn't show " .. ChatTypeName(group) .. " messages", function()
				frame:AddMessageGroup(group)
			end)
		end
		for _, group in ipairs(extra) do
			Add("also shows " .. ChatTypeName(group) .. " messages", function()
				frame:RemoveMessageGroup(group)
			end)
		end
	end

	if categories.messagesAndChannels and want.channels and have.channels then
		local missing, extra = SetDifference(have.channels, want.channels, ChannelKey)
		for _, channel in ipairs(missing) do
			local name = ClientChannelName(channel)
			Add("doesn't show the " .. name .. " channel", function()
				frame:AddChannel(name)
			end)
		end
		-- The live name is already in this client's language.
		for _, channel in ipairs(extra) do
			Add("also shows the " .. channel.name .. " channel", function()
				frame:RemoveChannel(channel.name)
			end)
		end
	end
end

local function DiffColors(liveColors, profileColors, addDifference)
	local chatTypes = {}
	for chatType in pairs(profileColors) do
		table.insert(chatTypes, chatType)
	end
	table.sort(chatTypes)

	for _, chatType in ipairs(chatTypes) do
		local have, want = liveColors[chatType], profileColors[chatType]
		if have then
			if not SameColor(have, want) then
				addDifference("Different color for " .. ChatTypeName(chatType), function()
					ChangeChatColor(chatType, want.r, want.g, want.b)
				end)
			end
			-- Only chat types that support class-colored names report the flag.
			local bothKnown = have.classColoredNames ~= nil and want.classColoredNames ~= nil
			if bothKnown and have.classColoredNames ~= want.classColoredNames then
				addDifference("Different name coloring for " .. ChatTypeName(chatType), function()
					SetChatColorNameByClass(chatType, want.classColoredNames)
				end)
			end
		end
	end
end

local function IsCustomKey(key)
	return key:sub(1, 5) == "name:"
end

-- Returns a list of { text, apply, opensOrClosesTab }, one per setting that differs. `text`
-- says how the live settings differ from the profile, and `apply` makes them match. The panel
-- shows the text, and Apply runs the same entries, so the two can't disagree.
function ChatSettings.Diff(live, profile)
	local categories = profile.categories
	local differences = {}
	local function AddDifference(text, apply, opensOrClosesTab)
		table.insert(differences, { text = text, apply = apply, opensOrClosesTab = opensOrClosesTab })
	end

	local liveByKey, wanted = {}, {}
	for _, have in ipairs(live.windows) do
		liveByKey[have.key] = have
	end
	for _, want in ipairs(profile.windows) do
		wanted[want.key] = true
	end

	-- Tabs are closed first: if every window is in use, a new tab can't open until one closes.
	if categories.tabs then
		for _, have in ipairs(live.windows) do
			if IsCustomKey(have.key) and not wanted[have.key] then
				local frame = _G["ChatFrame" .. live.windowNumbers[have.key]]
				AddDifference('Extra tab "' .. have.name .. '"', function()
					FCF_Close(frame)
				end, true)
			end
		end
	end

	for _, want in ipairs(profile.windows) do
		local have = liveByKey[want.key]
		if have then
			DiffWindow(_G["ChatFrame" .. live.windowNumbers[want.key]], have, want, categories, AddDifference)
		elseif categories.tabs and IsCustomKey(want.key) then
			AddDifference('Missing tab "' .. want.name .. '"', function()
				FCF_OpenNewWindow(want.name, true) -- noDefaultChannels; the second pass adds the profile's own
			end, true)
		end
	end

	if categories.colors and profile.colors and live.colors then
		DiffColors(live.colors, profile.colors, AddDifference)
	end

	return differences
end

-- Applies a profile and returns what still differs afterward (empty means success), plus
-- the first error a change raised, if any.
--
-- Success means "nothing differs afterward", not "nothing raised an error", because some game
-- functions fail silently. Each change gets its own pcall so one failure doesn't stop the rest.
function ChatSettings.Apply(profile)
	local firstError
	local function ApplyDifferences(include)
		for _, difference in ipairs(ChatSettings.Diff(ChatSettings.Read(profile.categories), profile)) do
			if include(difference) then
				local ok, err = pcall(difference.apply)
				if not ok then
					firstError = firstError or err
				end
			end
		end
	end

	-- A tab has to exist before its font or channels can be set, so open and close tabs
	-- first, then compare again and do the rest.
	ApplyDifferences(function(difference)
		return difference.opensOrClosesTab
	end)
	ApplyDifferences(function(difference)
		return not difference.opensOrClosesTab
	end)
	return ChatSettings.Diff(ChatSettings.Read(profile.categories), profile), firstError
end
