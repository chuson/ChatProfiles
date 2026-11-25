-- Export strings, and checking imported ones. An imported string is untrusted, so
-- every field is checked and anything unexpected rejects the whole string: nothing
-- is clamped or quietly fixed, apart from removing "|" from names.

local _, ns = ...

local ExportString = {}
ns.ExportString = ExportString

-- Exports are CBOR, then Base64 so they paste cleanly. Bump the number if the format changes.
local EXPORT_PREFIX = "ChatProfiles1:"
local MAX_PASTE_LENGTH = 64 * 1024 -- checked before decoding, so a huge paste can't stall the game
local MAX_TEXT_LENGTH = 50
local MAX_LIST_LENGTH = 100 -- message groups or channels in one tab
local MAX_COLORS = 200
local MIN_FONT_SIZE, MAX_FONT_SIZE = 6, 40

local PROFILE_FIELDS = { categories = true, windows = true, colors = true }
local CATEGORIES = { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true }
local WINDOW_FIELDS = {
	key = true,
	name = true,
	fontSize = true,
	r = true,
	g = true,
	b = true,
	a = true,
	locked = true,
	messageGroups = true,
	channels = true,
}
local CHANNEL_FIELDS = { name = true, zoneChannelID = true }
local COLOR_FIELDS = { r = true, g = true, b = true, classColoredNames = true }

-- Validation stops at the first problem by raising an error, which ExportString.Validate catches.
-- Level 0 leaves the file and line number off the message.
local function Check(ok, reason)
	if not ok then
		error(reason, 0)
	end
end

-- For putting untrusted values into an error message that the panel shows.
local function SafeText(value)
	return (tostring(value):gsub("|", ""):sub(1, 30))
end

local function CheckFields(t, allowed, what)
	for field in pairs(t) do
		Check(allowed[field], "unknown field " .. SafeText(field) .. " in " .. what)
	end
end

-- Keys 1 to n with no gaps and nothing else. Doesn't rely on #t, which is unreliable with gaps.
local function CheckList(t, maxLength, what)
	Check(type(t) == "table", what .. " is not a list")
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	Check(count <= maxLength, "too many entries in " .. what)
	for i = 1, count do
		Check(t[i] ~= nil, what .. " is not a list")
	end
end

local function IsBetweenZeroAndOne(value)
	return type(value) == "number" and value >= 0 and value <= 1
end

local function CheckColor(t, what)
	local valid = IsBetweenZeroAndOne(t.r) and IsBetweenZeroAndOne(t.g) and IsBetweenZeroAndOne(t.b)
	Check(valid, what .. " needs red, green and blue values between 0 and 1")
end

local function CheckOpacity(value, what)
	Check(IsBetweenZeroAndOne(value), what .. " must be between 0 and 1")
end

local function CheckBoolean(value, what)
	Check(value == nil or type(value) == "boolean", what .. " must be true or false")
end

-- "|" starts the client's color and link escape codes, so it's stripped from anything shown as a name.
local function CleanName(value, what)
	Check(type(value) == "string", what .. " is not text")
	local name = value:gsub("|", "")
	Check(name ~= "" and #name <= MAX_TEXT_LENGTH, what .. " is empty or too long")
	return name
end

local function ValidateWindow(window, what)
	Check(type(window) == "table", what .. " is not a table")
	CheckFields(window, WINDOW_FIELDS, what)

	local clean = { name = CleanName(window.name, what .. " name") }
	if window.key == "window:1" or window.key == "window:2" then
		clean.key = window.key
	else
		Check(type(window.key) == "string" and window.key:sub(1, 5) == "name:", what .. " has an invalid key")
		clean.key = "name:" .. clean.name
	end

	local fontSize = window.fontSize
	if fontSize ~= nil then
		local valid = type(fontSize) == "number"
			and fontSize % 1 == 0
			and (fontSize == 0 or (fontSize >= MIN_FONT_SIZE and fontSize <= MAX_FONT_SIZE))
		Check(valid, what .. " has an invalid font size")
		clean.fontSize = fontSize
	end

	if window.r ~= nil or window.g ~= nil or window.b ~= nil then
		CheckColor(window, what .. " background color")
		clean.r, clean.g, clean.b = window.r, window.g, window.b
	end
	if window.a ~= nil then
		CheckOpacity(window.a, what .. " opacity")
		clean.a = window.a
	end

	CheckBoolean(window.locked, what .. " lock")
	clean.locked = window.locked

	if window.messageGroups ~= nil then
		CheckList(window.messageGroups, MAX_LIST_LENGTH, what .. " message groups")
		clean.messageGroups = {}
		for i = 1, #window.messageGroups do
			local group = window.messageGroups[i]
			local valid = type(group) == "string" and #group <= MAX_TEXT_LENGTH and group:match("^[%u%d_]+$")
			Check(valid, what .. " has an invalid message group")
			clean.messageGroups[i] = group
		end
	end

	if window.channels ~= nil then
		CheckList(window.channels, MAX_LIST_LENGTH, what .. " channels")
		clean.channels = {}
		for i = 1, #window.channels do
			local channel = window.channels[i]
			Check(type(channel) == "table", what .. " has an invalid channel")
			CheckFields(channel, CHANNEL_FIELDS, what .. " channel")
			local id = channel.zoneChannelID
			Check(type(id) == "number" and id >= 0 and id % 1 == 0, what .. " has an invalid channel ID")
			clean.channels[i] = { name = CleanName(channel.name, what .. " channel name"), zoneChannelID = id }
		end
	end

	return clean
end

local function ValidateColors(colors)
	Check(type(colors) == "table", "chat colors are not a table")
	local clean, count = {}, 0
	for chatType, color in pairs(colors) do
		count = count + 1
		Check(count <= MAX_COLORS, "too many chat colors")
		Check(type(chatType) == "string" and ChatTypeInfo[chatType] ~= nil, "unknown chat type " .. SafeText(chatType))
		Check(type(color) == "table", chatType .. " color is not a table")
		CheckFields(color, COLOR_FIELDS, chatType .. " color")
		CheckColor(color, chatType .. " color")
		CheckBoolean(color.classColoredNames, chatType .. " class-colored names")
		clean[chatType] = { r = color.r, g = color.g, b = color.b, classColoredNames = color.classColoredNames }
	end
	return clean
end

local function CleanProfile(data)
	Check(type(data) == "table", "not a profile")
	CheckFields(data, PROFILE_FIELDS, "profile")

	Check(type(data.categories) == "table", "the profile has no categories")
	CheckFields(data.categories, CATEGORIES, "categories")
	local categories = {}
	for category in pairs(CATEGORIES) do
		CheckBoolean(data.categories[category], category)
		categories[category] = data.categories[category] == true
	end

	CheckList(data.windows, Constants.ChatFrameConstants.MaxChatWindows, "tabs")
	local windows, seen = {}, {}
	for i = 1, #data.windows do
		local window = ValidateWindow(data.windows[i], "tab " .. i)
		Check(not seen[window.key], "two tabs are named " .. window.name)
		seen[window.key] = true
		windows[i] = window
	end

	local profile = { categories = categories, windows = windows }
	if data.colors ~= nil then
		profile.colors = ValidateColors(data.colors)
	end
	return profile
end

-- Returns a clean copy of `data`, or nil and the reason it was rejected.
function ExportString.Validate(data)
	local ok, result = pcall(CleanProfile, data)
	if ok then
		return result
	end
	return nil, result
end

function ExportString.Export(profile)
	local data = { categories = profile.categories, windows = profile.windows, colors = profile.colors }
	return EXPORT_PREFIX .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR(data))
end

-- Returns a profile, or nil and a reason to show the user.
function ExportString.Import(text)
	if #text > MAX_PASTE_LENGTH then
		return nil, "the text is too long to be a Chat Profiles export"
	end
	text = text:match("^%s*(.-)%s*$")
	if text == "" then
		return nil, "the box is empty"
	elseif text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
		return nil, "that isn't a Chat Profiles export"
	end

	-- Both decoders raise errors on bad input instead of returning nil.
	local ok, data = pcall(function()
		return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(text:sub(#EXPORT_PREFIX + 1)))
	end)
	if not ok then
		return nil, "part of the text is missing or damaged. Try copying it again"
	end
	return ExportString.Validate(data)
end
