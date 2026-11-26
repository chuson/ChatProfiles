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
	local name, fontSize, r, g, b, a, _, locked, docked = GetChatWindowInfo(windowNumber)
	local window = { key = key, name = name }
	if categories.tabs then
		window.locked = locked
		window.docked = docked ~= nil
		-- Docked tabs follow General. A tab keeps its saved position after it's docked again, so
		-- only an undocked tab's position means anything.
		if not docked then
			window.point, window.xOffset, window.yOffset = GetChatWindowSavedPosition(windowNumber)
			window.width, window.height = GetChatWindowSavedDimensions(windowNumber)
		end
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

	-- New tabs are added to the end of the dock, so creating them in dock order reproduces the layout.
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

-- Saved positions are fractions of the screen size, and 0.001 is about a pixel or two.
local function SamePosition(have, want)
	return have.point == want.point
		and math.abs(have.xOffset - want.xOffset) < 0.001
		and math.abs(have.yOffset - want.yOffset) < 0.001
end

-- Saved sizes come back as fractions of a pixel off, e.g. 429.99997 for 430.
local function SameSize(have, want)
	return math.abs(have.width - want.width) < 0.5 and math.abs(have.height - want.height) < 0.5
end

-- A setting the profile doesn't have (nil) is left alone. So is font size 0, which means it
-- was never set. `dockIndex` is where the tab goes if it has to be docked.
local function DiffWindow(frame, have, want, categories, dockIndex, addDifference)
	local function Add(text, apply)
		addDifference(have.name .. ": " .. text, apply)
	end

	if categories.tabs then
		if want.docked ~= nil and have.docked ~= want.docked then
			if want.docked then
				Add("undocked instead of docked", function()
					FCF_DockFrame(frame, dockIndex)
				end)
			else
				Add("docked instead of undocked", function()
					-- FCF_UnDockFrame leaves the tab in the dock's tab bar, and a docked tab that
					-- wasn't selected stays hidden. FCF_ToggleLock's unlock path fixes both this way.
					FCF_UnDockFrame(frame)
					FCF_SetTabPosition(frame, 0)
					FCF_CheckShowChatFrame(frame)
					FCF_CheckShowChatFrame(_G[frame:GetName() .. "Tab"])
				end)
			end
		end
		-- A tab that was just docked or undocked has no position read yet, so it counts as moved.
		if want.docked == false and want.point and (not have.point or not SamePosition(have, want)) then
			Add("different position", function()
				SetChatWindowSavedPosition(frame:GetID(), want.point, want.xOffset, want.yOffset)
				FCF_RestorePositionAndDimensions(frame)
			end)
		end
		if want.docked == false and want.width and (not have.width or not SameSize(have, want)) then
			Add("different size", function()
				SetChatWindowSavedDimensions(frame:GetID(), want.width, want.height)
				FCF_RestorePositionAndDimensions(frame)
			end)
		end
		-- After the dock change, since docking a tab locks it.
		if want.locked ~= nil and have.locked ~= want.locked then
			Add("locked differently", function()
				FCF_SetLocked(frame, want.locked)
			end)
		end
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

-- FCF_DockFrame returns early for a tab that's already docked, so each tab is undocked and
-- docked again at its place, after General, which never moves. Undocking the selected tab
-- changes the selection, so it's selected again afterward.
local function RedockInOrder(frames)
	local selected = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
	for i, frame in ipairs(frames) do
		FCF_UnDockFrame(frame)
		FCF_DockFrame(frame, i + 1)
	end
	if selected then
		FCFDock_SelectWindow(GENERAL_CHAT_DOCK, selected)
	end
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

	-- Profiles list their docked tabs first, in dock order, so counting them gives each one's
	-- place in the dock. A profile saved before dock state was stored counts as all docked.
	local liveByKey, wanted, dockIndex, dockedCount = {}, {}, {}, 0
	for _, have in ipairs(live.windows) do
		liveByKey[have.key] = have
	end
	for _, want in ipairs(profile.windows) do
		wanted[want.key] = want
		if want.docked ~= false then
			dockedCount = dockedCount + 1
			dockIndex[want.key] = dockedCount
		end
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

	-- Compares the tabs that are docked both live and in the profile, leaving out General. This
	-- comes before each tab's own changes, since docking a tab locks it. Tabs that are about to be
	-- docked are left out here and docked at their place by DiffWindow.
	if categories.tabs then
		local general = "window:" .. GENERAL_WINDOW
		local haveOrder, wantOrder = {}, {}
		for _, have in ipairs(live.windows) do
			local want = wanted[have.key]
			if have.key ~= general and have.docked and want and want.docked ~= false then
				table.insert(haveOrder, have.key)
			end
		end
		for _, want in ipairs(profile.windows) do
			local have = liveByKey[want.key]
			if want.key ~= general and want.docked ~= false and have and have.docked then
				table.insert(wantOrder, want.key)
			end
		end
		if table.concat(haveOrder, "\n") ~= table.concat(wantOrder, "\n") then
			local frames = {}
			for i, key in ipairs(wantOrder) do
				frames[i] = _G["ChatFrame" .. live.windowNumbers[key]]
			end
			AddDifference("Tabs in a different order", function()
				RedockInOrder(frames)
			end)
		end
	end

	for _, want in ipairs(profile.windows) do
		local have = liveByKey[want.key]
		if have then
			local frame = _G["ChatFrame" .. live.windowNumbers[want.key]]
			DiffWindow(frame, have, want, categories, dockIndex[want.key], AddDifference)
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
