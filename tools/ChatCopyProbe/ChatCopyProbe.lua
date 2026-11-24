-- Throwaway diagnostic for ChatCopy open questions 1 and 2: when does the chat
-- setup settle after login, and can it still be read at logout?
-- Delete this addon once the answers are in the design doc.

local MAX_SESSIONS = 6
local LATE_CHECKS = { 2, 5, 15 } -- seconds after entering the world

local session = { started = date("%Y-%m-%d %H:%M:%S"), events = {} }
local startTime = GetTime()
local lastState

local function ReadChatState()
	local lines = {}
	for id = 1, Constants.ChatFrameConstants.MaxChatWindows do
		local name, size, _, _, _, _, shown, _, docked = GetChatWindowInfo(id)
		local groups = table.concat({ GetChatWindowMessages(id) }, ",")
		local channels = table.concat({ GetChatWindowChannels(id) }, ",")
		lines[#lines + 1] = string.format(
			"%d %s size=%s shown=%s docked=%s groups=%s channels=%s",
			id, tostring(name), tostring(size), tostring(shown), tostring(docked), groups, channels
		)
	end
	return lines
end

-- Only store the full state when it differs from the last recorded one,
-- so the log shows exactly when the setup changed.
local function Record(label)
	local entry = { label = label, t = string.format("%.2f", GetTime() - startTime) }
	local ok, lines = pcall(ReadChatState)
	if not ok then
		entry.error = lines
	else
		local state = table.concat(lines, "\n")
		if state == lastState then
			entry.chat = "unchanged"
		else
			entry.chat = lines
			lastState = state
		end
	end
	table.insert(session.events, entry)
end

local function Summary(entry)
	if entry.error then
		return "error: " .. entry.error
	end
	return entry.chat == "unchanged" and "unchanged" or "changed"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SETTINGS_LOADED")
frame:RegisterEvent("UPDATE_CHAT_WINDOWS")
frame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event, ...)
	local label = event

	if event == "ADDON_LOADED" then
		if ... ~= "ChatCopyProbe" then
			return
		end
		ChatCopyProbeDB = ChatCopyProbeDB or {}
		table.insert(ChatCopyProbeDB, session)
		while #ChatCopyProbeDB > MAX_SESSIONS do
			table.remove(ChatCopyProbeDB, 1)
		end
	elseif event == "PLAYER_LOGIN" then
		-- Where the design doc currently plans to apply the profile.
		C_Timer.After(0, function()
			Record("one frame after PLAYER_LOGIN")
		end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		local isInitialLogin, isReload = ...
		label = string.format("%s initial=%s reload=%s", event, tostring(isInitialLogin), tostring(isReload))
		if isInitialLogin or isReload then
			for _, delay in ipairs(LATE_CHECKS) do
				C_Timer.After(delay, function()
					Record(delay .. "s after PLAYER_ENTERING_WORLD")
				end)
			end
		end
	end

	Record(label)
end)

SLASH_CHATCOPYPROBE1 = "/ccprobe"
SlashCmdList.CHATCOPYPROBE = function()
	print("ChatCopy Probe, this session:")
	for _, entry in ipairs(session.events) do
		print(entry.t, entry.label, Summary(entry))
	end

	local previous = ChatCopyProbeDB and ChatCopyProbeDB[#ChatCopyProbeDB - 1]
	if previous and #previous.events > 0 then
		local last = previous.events[#previous.events]
		print("Previous session ended with:", last.label, Summary(last))
	end
end
