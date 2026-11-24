-- Export strings, and checking imported ones. An imported string is untrusted, so
-- every field is checked and anything unexpected rejects the whole string: nothing
-- is clamped or quietly fixed, apart from removing "|" from names.

local _, ns = ...

local Codec = {}
ns.Codec = Codec

local PREFIX = "ChatCopy1:"
local MAX_INPUT_LENGTH = 64 * 1024
local MAX_NAME_LENGTH = 50
local MAX_LIST_LENGTH = 100 -- message groups or channels in one tab
local MAX_COLORS = 200
local MIN_FONT_SIZE, MAX_FONT_SIZE = 6, 40

local PROFILE_FIELDS = { include = true, windows = true, colors = true }
local CATEGORIES = { tabs = true, contents = true, look = true, colors = true }
local WINDOW_FIELDS = {
	key = true,
	name = true,
	size = true,
	r = true,
	g = true,
	b = true,
	a = true,
	locked = true,
	groups = true,
	channels = true,
}
local CHANNEL_FIELDS = { name = true, zoneID = true }
local COLOR_FIELDS = { r = true, g = true, b = true, classColor = true }

local function Check(ok, reason)
	if not ok then
		error(reason, 0)
	end
end

-- For putting untrusted values into an error message that the panel shows.
local function Quote(value)
	return (tostring(value):gsub("|", ""):sub(1, 30))
end

local function CheckFields(t, allowed, what)
	for field in pairs(t) do
		Check(allowed[field], "unknown field " .. Quote(field) .. " in " .. what)
	end
end

local function CheckList(t, maxLength, what)
	Check(type(t) == "table", what .. " is not a list")
	Check(#t <= maxLength, "too many entries in " .. what)
	for k in pairs(t) do
		Check(type(k) == "number" and k >= 1 and k <= #t and k % 1 == 0, what .. " is not a list")
	end
end

local function CheckUnit(value, what)
	Check(type(value) == "number" and value >= 0 and value <= 1, what .. " must be between 0 and 1")
end

local function CheckBoolean(value, what)
	Check(value == nil or type(value) == "boolean", what .. " must be true or false")
end

-- "|" starts the client's display escape codes, so it is removed from anything shown as a name.
local function CleanName(value, what)
	Check(type(value) == "string", what .. " is not text")
	local name = value:gsub("|", "")
	Check(name ~= "" and #name <= MAX_NAME_LENGTH, what .. " is empty or too long")
	return name
end

local function ValidateWindow(window, what)
	Check(type(window) == "table", what .. " is not a table")
	CheckFields(window, WINDOW_FIELDS, what)

	local clean = { name = CleanName(window.name, what .. " name") }
	if window.key == "id:1" or window.key == "id:2" then
		clean.key = window.key
	else
		Check(type(window.key) == "string" and window.key:sub(1, 5) == "name:", what .. " has an invalid key")
		clean.key = "name:" .. clean.name
	end

	local size = window.size
	if size ~= nil then
		local valid = type(size) == "number"
			and size % 1 == 0
			and (size == 0 or (size >= MIN_FONT_SIZE and size <= MAX_FONT_SIZE))
		Check(valid, what .. " has an invalid font size")
		clean.size = size
	end

	if window.r ~= nil or window.g ~= nil or window.b ~= nil then
		CheckUnit(window.r, what .. " red")
		CheckUnit(window.g, what .. " green")
		CheckUnit(window.b, what .. " blue")
		clean.r, clean.g, clean.b = window.r, window.g, window.b
	end
	if window.a ~= nil then
		CheckUnit(window.a, what .. " opacity")
		clean.a = window.a
	end

	CheckBoolean(window.locked, what .. " lock")
	clean.locked = window.locked

	if window.groups ~= nil then
		CheckList(window.groups, MAX_LIST_LENGTH, what .. " message groups")
		clean.groups = {}
		for i = 1, #window.groups do
			local group = window.groups[i]
			local valid = type(group) == "string" and #group <= MAX_NAME_LENGTH and group:match("^[%u%d_]+$")
			Check(valid, what .. " has an invalid message group")
			clean.groups[i] = group
		end
	end

	if window.channels ~= nil then
		CheckList(window.channels, MAX_LIST_LENGTH, what .. " channels")
		clean.channels = {}
		for i = 1, #window.channels do
			local channel = window.channels[i]
			Check(type(channel) == "table", what .. " has an invalid channel")
			CheckFields(channel, CHANNEL_FIELDS, what .. " channel")
			local zoneID = channel.zoneID
			Check(type(zoneID) == "number" and zoneID >= 0 and zoneID % 1 == 0, what .. " has an invalid channel ID")
			clean.channels[i] = { name = CleanName(channel.name, what .. " channel name"), zoneID = zoneID }
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
		Check(type(chatType) == "string" and ChatTypeInfo[chatType] ~= nil, "unknown chat type " .. Quote(chatType))
		Check(type(color) == "table", chatType .. " color is not a table")
		CheckFields(color, COLOR_FIELDS, chatType .. " color")
		CheckUnit(color.r, chatType .. " red")
		CheckUnit(color.g, chatType .. " green")
		CheckUnit(color.b, chatType .. " blue")
		CheckBoolean(color.classColor, chatType .. " class-colored names")
		clean[chatType] = { r = color.r, g = color.g, b = color.b, classColor = color.classColor }
	end
	return clean
end

local function BuildProfile(data)
	Check(type(data) == "table", "not a profile")
	CheckFields(data, PROFILE_FIELDS, "profile")

	Check(type(data.include) == "table", "the profile has no categories")
	CheckFields(data.include, CATEGORIES, "categories")
	local include = {}
	for category in pairs(CATEGORIES) do
		CheckBoolean(data.include[category], category)
		include[category] = data.include[category] == true
	end

	CheckList(data.windows, Constants.ChatFrameConstants.MaxChatWindows, "tabs")
	local windows, seen = {}, {}
	for i = 1, #data.windows do
		local window = ValidateWindow(data.windows[i], "tab " .. i)
		Check(not seen[window.key], "two tabs are named " .. window.name)
		seen[window.key] = true
		windows[i] = window
	end

	local profile = { include = include, windows = windows }
	if data.colors ~= nil then
		profile.colors = ValidateColors(data.colors)
	end
	return profile
end

-- Returns a clean copy of `data`, or nil and the reason it was rejected.
function Codec.Validate(data)
	local ok, result = pcall(BuildProfile, data)
	if ok then
		return result
	end
	return nil, result
end

function Codec.Export(profile)
	local data = { include = profile.include, windows = profile.windows, colors = profile.colors }
	return PREFIX .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR(data))
end

-- Returns a profile, or nil and a reason to show the user.
function Codec.Import(text)
	if #text > MAX_INPUT_LENGTH then
		return nil, "the text is too long to be a ChatCopy profile"
	end
	text = text:match("^%s*(.-)%s*$")
	if text == "" then
		return nil, "the box is empty"
	elseif text:sub(1, #PREFIX) ~= PREFIX then
		return nil, "that isn't a ChatCopy profile"
	end

	local ok, data = pcall(function()
		return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(text:sub(#PREFIX + 1)))
	end)
	if not ok then
		return nil, "part of the text is missing or damaged. Try copying it again"
	end
	return Codec.Validate(data)
end
