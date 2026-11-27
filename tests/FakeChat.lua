-- A working model of the client's chat windows and dock, so tests can apply a profile and check
-- that nothing differs afterward. The other tests record which game calls a change makes; this
-- one checks that those calls, made in order, have the intended effect.
--
-- It follows Blizzard's FloatingChatFrame.lua (12.1.5), and questions 3, 4 and 7 in section 10
-- of the design doc:
-- - FCF_OpenNewWindow takes the first custom window that's neither shown nor docked, resets its
--   colors and clears its groups and channels (noDefaultChannels), unlocks it, then docks it at
--   the end and selects it. Docking locks it again.
-- - FCF_Close undocks and hides a window and clears its groups and channels. It keeps its name.
--   It does nothing to General.
-- - FCF_DockFrame does nothing for a tab that's already docked, inserts at the index it's given
--   (appending past the end), and locks the tab. Only General may go at index 1.
-- - FCF_UnDockFrame does nothing to General. Undocking shows the frame, and if it was selected,
--   selects the first docked tab.
-- - The dock keeps tabs in the order they were docked, and the docked index the client reports
--   is that order. It draws General and the Combat Log first (isStaticDocked), but that doesn't
--   change the order.
-- - Unlocking a docked tab undocks it, so only General can be docked and unlocked.
-- - Colors and opacity are stored as 0-255, so they read back rounded.

local helpers = dofile("tests/helpers.lua")

local FakeChat = {}

local MAX_WINDOWS, RESERVED_WINDOWS = 10, 3
local GENERAL, COMBAT_LOG = 1, 2
local DEFAULT_GROUPS = { "SAY", "EMOTE", "YELL", "GUILD", "WHISPER", "PARTY", "RAID", "SYSTEM" }
local ZONE_CHANNELS = { [1] = "General", [2] = "Trade", [22] = "LocalDefense" }

local windows -- [window number] = the window's settings
local dock -- docked window numbers, in the order the dock draws them
local selected -- the selected docked window
local colorEntries -- what the ChatTypeInfo proxy holds

local function Rounded(value)
	return math.floor(value * 255 + 0.5) / 255
end

local function IndexOf(list, value)
	for i, item in ipairs(list) do
		if item == value then
			return i
		end
	end
end

-- The selected docked tab is shown and the others are hidden (FCFDock_UpdateTabs).
local function Select(windowNumber)
	selected = windowNumber
	for _, docked in ipairs(dock) do
		windows[docked].shown = docked == windowNumber
	end
end

local function Dock(windowNumber, index)
	if IndexOf(dock, windowNumber) then
		return
	end
	if index and index <= #dock + 1 then
		-- FCFDock_AddChatFrame asserts this.
		assert(index ~= 1 or windowNumber == GENERAL, "only General can be docked first")
		table.insert(dock, index, windowNumber)
	else
		table.insert(dock, windowNumber)
	end
	Select(selected)
	windows[windowNumber].locked = true
end

local function Undock(windowNumber)
	local index = IndexOf(dock, windowNumber)
	if windowNumber == GENERAL or not index then
		return
	end
	table.remove(dock, index)
	if selected == windowNumber then
		Select(dock[1])
	end
	windows[windowNumber].shown = true
end

local function NumberOf(frame)
	return frame:GetID()
end

local function NewWindow(name)
	return {
		name = name or "",
		fontSize = 14,
		r = 0,
		g = 0,
		b = 0,
		a = Rounded(0.25),
		shown = false,
		locked = false,
		messageGroups = {},
		channels = {},
		position = { "TOPLEFT", 0, 0 },
		size = { 430, 120 },
	}
end

-- Zone channels are added by their local name and reported with their ID.
local function ChannelID(name)
	for id, zoneName in pairs(ZONE_CHANNELS) do
		if zoneName == name then
			return id
		end
	end
	return 0
end

-- Sets the game's globals to this model. Call before loading ChatSettings.lua.
function FakeChat.Install()
	Constants = { ChatFrameConstants = { MaxChatWindows = MAX_WINDOWS } }
	SAY, GUILD = "Say", "Guild"
	GENERAL_CHAT_DOCK = { name = "GENERAL_CHAT_DOCK" }

	C_ChatInfo = {
		GetNumReservedChatWindows = function()
			return RESERVED_WINDOWS
		end,
		GetChannelShortcutForChannelID = function(id)
			return ZONE_CHANNELS[id]
		end,
	}

	for windowNumber = 1, MAX_WINDOWS do
		local frame = { name = "ChatFrame" .. windowNumber }
		function frame.GetID()
			return windowNumber
		end
		function frame.GetName(self)
			return self.name
		end
		function frame.AddMessageGroup(_, group)
			if not IndexOf(windows[windowNumber].messageGroups, group) then
				table.insert(windows[windowNumber].messageGroups, group)
			end
		end
		function frame.RemoveMessageGroup(_, group)
			local index = IndexOf(windows[windowNumber].messageGroups, group)
			if index then
				table.remove(windows[windowNumber].messageGroups, index)
			end
		end
		function frame.AddChannel(_, name)
			for _, channel in ipairs(windows[windowNumber].channels) do
				if channel[1]:lower() == name:lower() then
					return
				end
			end
			table.insert(windows[windowNumber].channels, { name, ChannelID(name) })
		end
		function frame.RemoveChannel(_, name)
			local channels = windows[windowNumber].channels
			for i, channel in ipairs(channels) do
				if channel[1]:lower() == name:lower() then
					table.remove(channels, i)
					return
				end
			end
		end
		_G[frame.name] = frame
		_G[frame.name .. "Tab"] = { name = frame.name .. "Tab" }
	end

	function GetChatWindowInfo(windowNumber)
		local w = windows[windowNumber]
		return w.name, w.fontSize, w.r, w.g, w.b, w.a, w.shown, w.locked, IndexOf(dock, windowNumber), false
	end
	function GetChatWindowMessages(windowNumber)
		return helpers.Unpack(windows[windowNumber].messageGroups)
	end
	function GetChatWindowChannels(windowNumber)
		local values = {}
		for _, channel in ipairs(windows[windowNumber].channels) do
			table.insert(values, channel[1])
			table.insert(values, channel[2])
		end
		return helpers.Unpack(values)
	end
	function GetChatWindowSavedPosition(windowNumber)
		return helpers.Unpack(windows[windowNumber].position)
	end
	function GetChatWindowSavedDimensions(windowNumber)
		return helpers.Unpack(windows[windowNumber].size)
	end
	function SetChatWindowSavedPosition(windowNumber, point, xOffset, yOffset)
		windows[windowNumber].position = { point, xOffset, yOffset }
	end
	function SetChatWindowSavedDimensions(windowNumber, width, height)
		windows[windowNumber].size = { width, height }
	end

	function FCF_OpenNewWindow(name, noDefaultChannels)
		for windowNumber = RESERVED_WINDOWS + 1, MAX_WINDOWS do
			local w = windows[windowNumber]
			if not w.shown and not IndexOf(dock, windowNumber) then
				local defaults = NewWindow(name)
				w.name, w.r, w.g, w.b, w.a = name, defaults.r, defaults.g, defaults.b, defaults.a
				w.locked = false
				w.messageGroups = noDefaultChannels and {} or helpers.DeepCopy(DEFAULT_GROUPS)
				w.channels = {}
				w.shown = true
				Dock(windowNumber, #dock + 1)
				Select(windowNumber)
				return _G["ChatFrame" .. windowNumber], windowNumber
			end
		end
	end
	function FCF_Close(frame)
		local windowNumber = NumberOf(frame)
		if windowNumber == GENERAL then
			return
		end
		Undock(windowNumber)
		windows[windowNumber].shown = false
		windows[windowNumber].messageGroups = {}
		windows[windowNumber].channels = {}
	end
	function FCF_DockFrame(frame, index)
		Dock(NumberOf(frame), index)
	end
	function FCF_UnDockFrame(frame)
		Undock(NumberOf(frame))
	end
	function FCF_CheckShowChatFrame(frame)
		-- Also called with a tab, which this model doesn't track.
		if frame.GetID then
			windows[NumberOf(frame)].shown = true
		end
	end
	function FCF_SetTabPosition() end
	function FCF_RestorePositionAndDimensions() end
	function FCF_SetLocked(frame, locked)
		windows[NumberOf(frame)].locked = locked
	end
	function FCF_SetChatWindowFontSize(_, frame, fontSize)
		windows[NumberOf(frame)].fontSize = fontSize
	end
	function FCF_SetWindowColor(frame, r, g, b)
		local w = windows[NumberOf(frame)]
		w.r, w.g, w.b = Rounded(r), Rounded(g), Rounded(b)
	end
	function FCF_SetWindowAlpha(frame, a)
		windows[NumberOf(frame)].a = Rounded(a)
	end
	function FCFDock_GetSelectedWindow()
		return _G["ChatFrame" .. selected]
	end
	function FCFDock_SelectWindow(_, frame)
		Select(NumberOf(frame))
	end

	function ChangeChatColor(chatType, r, g, b)
		local entry = colorEntries[chatType]
		entry.r, entry.g, entry.b = Rounded(r), Rounded(g), Rounded(b)
	end
	function SetChatColorNameByClass(chatType, enabled)
		colorEntries[chatType].colorNameByClass = enabled
	end
end

-- Sets up the client with `setup`, in the shape ChatSettings.Read returns: General and the Combat
-- Log, then custom tabs, which get windows 4, 5, ... in list order. Docked tabs are docked in list
-- order. Settings a window leaves out keep their defaults. `colors` maps chat types to
-- { r, g, b, classColoredNames }.
function FakeChat.Load(setup)
	windows, dock, selected = {}, {}, GENERAL
	for windowNumber = 1, MAX_WINDOWS do
		windows[windowNumber] = NewWindow()
	end
	windows[GENERAL].name, windows[COMBAT_LOG].name, windows[3].name = "General", "Combat Log", "Voice"

	local nextCustom = RESERVED_WINDOWS + 1
	for _, window in ipairs(setup.windows) do
		local windowNumber = tonumber(window.key:match("^window:(%d+)$"))
		if not windowNumber then
			windowNumber, nextCustom = nextCustom, nextCustom + 1
		end
		local w = windows[windowNumber]
		w.name = window.name
		w.fontSize = window.fontSize or w.fontSize
		if window.r then
			w.r, w.g, w.b = Rounded(window.r), Rounded(window.g), Rounded(window.b)
		end
		w.a = window.a and Rounded(window.a) or w.a
		w.messageGroups = helpers.DeepCopy(window.messageGroups or {})
		w.channels = {}
		for _, channel in ipairs(window.channels or {}) do
			table.insert(w.channels, { channel.name, channel.zoneChannelID })
		end
		if window.point then
			w.position = { window.point, window.xOffset, window.yOffset }
		end
		if window.width then
			w.size = { window.width, window.height }
		end
		w.locked = window.locked or false
		if window.docked == false then
			w.shown = true
		else
			-- A setup the client can't be in would make the tests prove nothing.
			assert(w.locked or windowNumber == GENERAL, window.name .. " is docked but unlocked")
			table.insert(dock, windowNumber)
		end
	end
	-- General can't be undocked, so it's always in the dock, first.
	local generalIndex = IndexOf(dock, GENERAL)
	if generalIndex then
		table.remove(dock, generalIndex)
	end
	table.insert(dock, 1, GENERAL)
	Select(GENERAL)

	colorEntries = {}
	for chatType, color in pairs(setup.colors or {}) do
		colorEntries[chatType] = {
			r = Rounded(color.r),
			g = Rounded(color.g),
			b = Rounded(color.b),
			colorNameByClass = color.classColoredNames,
		}
	end
	ChatTypeInfo = helpers.ChatTypeInfoProxy(colorEntries)
end

-- The docked windows' numbers, in the order the dock draws them.
function FakeChat.Dock()
	return helpers.DeepCopy(dock)
end

return FakeChat
