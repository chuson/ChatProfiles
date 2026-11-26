-- Tests for ExportString: reading pasted text, exporting, and the validator against good and
-- malformed profiles.

local helpers = dofile("tests/helpers.lua")
local Check, Equal, Fail = helpers.Check, helpers.Equal, helpers.Fail

-- Stand-ins for the game globals that ExportString reads. Serializing stores the table under a
-- token instead of encoding it, so the tests can check what Import decodes without real CBOR.
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
local chatTypes = { SAY = {}, GUILD = {}, CHANNEL1 = {} }
for i = 1, 201 do
	chatTypes["TYPE" .. i] = {}
end
ChatTypeInfo = helpers.ChatTypeInfoProxy(chatTypes)

local serialized, serializedCount = {}, 0
local decodedText
C_EncodingUtil = {
	SerializeCBOR = function(data)
		serializedCount = serializedCount + 1
		local token = "cbor" .. serializedCount
		serialized[token] = data
		return token
	end,
	EncodeBase64 = function(text)
		return text
	end,
	DecodeBase64 = function(text)
		decodedText = text
		if text == "damaged" then
			error("not Base64")
		end
		return text
	end,
	DeserializeCBOR = function(token)
		return serialized[token]
	end,
}

local ns = {}
helpers.LoadAddonFile("ChatProfiles/ExportString.lua", ns)
local Validate, Import, Export = ns.ExportString.Validate, ns.ExportString.Import, ns.ExportString.Export

local HANGUL_SYLLABLE = "\237\149\156" -- U+D55C, 3 bytes in UTF-8

local function GoodProfile()
	return {
		categories = { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true },
		windows = {
			{
				key = "window:1",
				name = "General",
				fontSize = 0,
				r = 0,
				g = 0,
				b = 0,
				a = 0.25,
				locked = true,
				messageGroups = { "SAY", "SYSTEM_NOMENU", "GUILD" },
				channels = { { name = "Trade", zoneChannelID = 2 }, { name = "MyChannel", zoneChannelID = 0 } },
			},
			{ key = "window:2", name = "Combat Log", fontSize = 14 },
			{ key = "name:trade", name = "trade", messageGroups = {}, channels = {} },
		},
		colors = { SAY = { r = 1, g = 1, b = 1 }, GUILD = { r = 0.25, g = 1, b = 0.25, classColoredNames = true } },
	}
end

-- Validates a good profile after `change` edits it. `change` may also return a replacement.
local function ValidateChanged(change)
	local data = GoodProfile()
	if change then
		data = change(data) or data
	end
	return Validate(data)
end

local function Accepts(description, change)
	local result, reason = ValidateChanged(change)
	Check(result ~= nil, description .. " was rejected: " .. tostring(reason))
	return result
end

-- `expected` is part of the reason the profile should be rejected for. Checking it means a
-- test can't pass because some earlier check happened to reject the profile.
local function Rejects(description, expected, change)
	local result, reason = ValidateChanged(change)
	if result ~= nil then
		Fail(description .. " was accepted")
	elseif not reason:find(expected, 1, true) then
		Fail(description .. ' was rejected for the wrong reason: "' .. reason .. '"')
	end
	return reason
end

local function RejectsImport(description, text, expected)
	local result, reason = Import(text)
	if result ~= nil then
		Fail(description .. " was imported")
	elseif not reason:find(expected, 1, true) then
		Fail(description .. ' was rejected for the wrong reason: "' .. reason .. '"')
	end
end

-- Reading pasted text

Import("  ChatProfiles1:ab\r\ncd ef\n")
Equal(decodedText, "abcdef", "spaces and line breaks inside a pasted export weren't removed")

RejectsImport("an empty box", "", "the box is empty")
RejectsImport("a box with only spaces", "  \r\n ", "the box is empty")
RejectsImport("a paste over 64 KB", "ChatProfiles1:" .. string.rep("A", 64 * 1024), "too long")
RejectsImport("text from another addon", "ChatCopy1:abc", "isn't a ChatProfiles export")
RejectsImport("text the decoder can't read", "ChatProfiles1:damaged", "missing or damaged")
local notAProfile = "ChatProfiles1:" .. C_EncodingUtil.SerializeCBOR({})
RejectsImport("decoded data that isn't a valid profile", notAProfile, "no categories")

-- Exporting

local exported = Export(GoodProfile())
Check(exported:sub(1, 14) == "ChatProfiles1:", "an export doesn't start with the prefix: " .. exported)
Equal(Import(exported), GoodProfile(), "a profile changed between Export and Import")

-- Accepted

local complete = Accepts("a complete profile")
Equal(complete, GoodProfile(), "Validate changed a valid profile")

Accepts("a profile without colors", function(p)
	p.colors = nil
end)
Accepts("a tab with only a key and name", function(p)
	p.windows = { { key = "name:x", name = "x" } }
end)

local fewerCategories = Accepts("categories that are left out", function(p)
	p.categories = { tabs = true }
end)
if fewerCategories then
	local expected = { tabs = true, messagesAndChannels = false, fontAndBackground = false, colors = false }
	Equal(fewerCategories.categories, expected, "categories that are left out didn't become false")
end

local input = GoodProfile()
local copy = Validate(input)
if copy then
	local shared = copy.windows[1] == input.windows[1] or copy.windows[1].channels == input.windows[1].channels
	Check(not shared, "Validate returned the imported tables instead of copies")
end

local unusualName = "a||b " .. HANGUL_SYLLABLE
local kept = Accepts("names with a literal | and non-ASCII characters", function(p)
	p.windows[3].name = unusualName
	p.windows[3].key = "name:anything"
	p.windows[1].channels[2].name = HANGUL_SYLLABLE
end)
if kept then
	Equal(kept.windows[3].name, unusualName, "a tab name was changed on import")
	Equal(kept.windows[3].key, "name:" .. unusualName, "a custom tab's key wasn't rebuilt from its name")
	Equal(kept.windows[1].channels[2].name, HANGUL_SYLLABLE, "a channel name was changed on import")
end

-- Makes a tab undocked, with the position and size the client recorded for an undocked window.
local function Undock(window)
	window.docked = false
	window.point, window.xOffset, window.yOffset = "TOPLEFT", 0.13828800618649, -0.25551301240921
	window.width, window.height = 429.99996948242, 119.99989318848
	return window
end

local undocked = Accepts("an undocked tab with a position and size", function(p)
	Undock(p.windows[3])
end)
if undocked then
	Equal(undocked.windows[3], Undock(GoodProfile().windows[3]), "an undocked tab changed on import")
end
Accepts("docked tabs", function(p)
	p.windows[1].docked = true
	p.windows[3].docked = true
end)
Accepts("an undocked Combat Log", function(p)
	Undock(p.windows[2])
end)

-- Limits, from the accepted side

Accepts("a name of exactly 200 bytes", function(p)
	p.windows[3].name = string.rep("a", 200)
end)
Accepts("exactly 10 tabs", function(p)
	for i = 4, 10 do
		p.windows[i] = { key = "name:t" .. i, name = "t" .. i }
	end
end)
Accepts("exactly 100 message groups", function(p)
	for i = 1, 100 do
		p.windows[1].messageGroups[i] = "SAY"
	end
end)
Accepts("exactly 100 channels", function(p)
	for i = 1, 100 do
		p.windows[1].channels[i] = { name = "c" .. i, zoneChannelID = 0 }
	end
end)
Accepts("the smallest and largest font sizes", function(p)
	p.windows[1].fontSize = 6
	p.windows[2].fontSize = 40
end)
Accepts("colors and opacity of exactly 0 and 1", function(p)
	p.windows[1].r, p.windows[1].g, p.windows[1].b, p.windows[1].a = 1, 0, 1, 0
	p.windows[2].a = 1
end)
Accepts("position offsets of exactly -1 and 1", function(p)
	Undock(p.windows[3])
	p.windows[3].xOffset, p.windows[3].yOffset = 1, -1
end)
Accepts("a size of exactly 4096", function(p)
	Undock(p.windows[3])
	p.windows[3].width, p.windows[3].height = 4096, 4096
end)
Accepts("exactly 200 chat colors", function(p)
	p.colors = {}
	for i = 1, 200 do
		p.colors["TYPE" .. i] = { r = 0, g = 0, b = 0 }
	end
end)

-- Rejected: the profile and its categories

Rejects("not a table", "not a profile", function()
	return "ChatProfiles"
end)
Rejects("an unknown top-level field", "unknown field extra in profile", function(p)
	p.extra = true
end)
Rejects("missing categories", "no categories", function(p)
	p.categories = nil
end)
Rejects("an unknown category", "unknown field bogus in categories", function(p)
	p.categories.bogus = true
end)
Rejects("a category that is not a boolean", "tabs must be true or false", function(p)
	p.categories.tabs = 1
end)

-- Rejected: the tab list

Rejects("missing tabs", "tabs is not a list", function(p)
	p.windows = nil
end)
Rejects("tabs that are not a list", "tabs is not a list", function(p)
	p.windows = { first = p.windows[1] }
end)
Rejects("a hole in the tab list", "tabs is not a list", function(p)
	p.windows[2] = nil
end)
Rejects("11 tabs", "too many entries in tabs", function(p)
	for i = 4, 11 do
		p.windows[i] = { key = "name:t" .. i, name = "t" .. i }
	end
end)
Rejects("two tabs with the same key", "two tabs are named trade", function(p)
	p.windows[4] = { key = "name:trade", name = "trade" }
end)
Rejects("two tabs with different keys but the same name", "two tabs are named trade", function(p)
	p.windows[4] = { key = "name:other", name = "trade" }
end)

-- Rejected: a tab

Rejects("a tab that isn't a table", "tab 1 is not a table", function(p)
	p.windows[1] = "General"
end)
Rejects("an unknown tab field", "unknown field script in tab 1", function(p)
	p.windows[1].script = "print(1)"
end)
Rejects("a reserved window that isn't General or Combat Log", "tab 1 has an invalid key", function(p)
	p.windows[1].key = "window:3"
end)
Rejects("a key without a prefix", "tab 3 has an invalid key", function(p)
	p.windows[3].key = "trade"
end)
Rejects("a font size of 5", "tab 1 has an invalid font size", function(p)
	p.windows[1].fontSize = 5
end)
Rejects("a font size of 41", "tab 1 has an invalid font size", function(p)
	p.windows[1].fontSize = 41
end)
Rejects("a fractional font size", "tab 1 has an invalid font size", function(p)
	p.windows[1].fontSize = 12.5
end)
Rejects("a color above 1", "tab 1 background color needs", function(p)
	p.windows[1].r = 1.5
end)
Rejects("a color given as text", "tab 1 background color needs", function(p)
	p.windows[1].g = "0"
end)
Rejects("only part of a color", "tab 2 background color needs", function(p)
	p.windows[2].r = 0.5
end)
Rejects("a negative opacity", "tab 1 opacity must be between 0 and 1", function(p)
	p.windows[1].a = -0.1
end)
Rejects("a lock that is not a boolean", "tab 1 lock must be true or false", function(p)
	p.windows[1].locked = 1
end)

-- Rejected: dock state, position and size

Rejects("a docked state that is not a boolean", "tab 1 docked state must be true or false", function(p)
	p.windows[1].docked = 1
end)
Rejects("an undocked General", "tab 1 is General, which can't be undocked", function(p)
	p.windows[1].docked = false
end)
Rejects("a position on a docked tab", "tab 3 has a position but isn't undocked", function(p)
	Undock(p.windows[3]).docked = true
end)
Rejects("a position with no dock state", "tab 3 has a position but isn't undocked", function(p)
	Undock(p.windows[3]).docked = nil
end)
Rejects("a corner that isn't one of the four", "tab 3 has an invalid position", function(p)
	Undock(p.windows[3]).point = "CENTER"
end)
Rejects("an offset past the edge of the screen", "tab 3 has an invalid position", function(p)
	Undock(p.windows[3]).xOffset = 1.5
end)
Rejects("an offset given as text", "tab 3 has an invalid position", function(p)
	Undock(p.windows[3]).yOffset = "0"
end)
Rejects("only part of a position", "tab 3 has an invalid position", function(p)
	Undock(p.windows[3]).point = nil
end)
Rejects("a size on a docked tab", "tab 3 has a size but isn't undocked", function(p)
	local window = Undock(p.windows[3])
	window.docked, window.point, window.xOffset, window.yOffset = true, nil, nil, nil
end)
Rejects("a width of 0", "tab 3 has an invalid size", function(p)
	Undock(p.windows[3]).width = 0
end)
Rejects("a height of 4097", "tab 3 has an invalid size", function(p)
	Undock(p.windows[3]).height = 4097
end)
Rejects("only part of a size", "tab 3 has an invalid size", function(p)
	Undock(p.windows[3]).height = nil
end)

-- Rejected: tab and channel names

Rejects("a name that isn't text", "tab 3 name is not text", function(p)
	p.windows[3].name = 5
end)
Rejects("an empty name", "tab 3 name is empty or too long", function(p)
	p.windows[3].name = ""
end)
Rejects("a name of 201 bytes", "tab 3 name is empty or too long", function(p)
	p.windows[3].name = string.rep("a", 201)
end)
Rejects("a name with a color code", "tab 3 name contains a color or link code", function(p)
	p.windows[3].name = "tr|cffff0000ade"
end)
Rejects("a name with a single | after a literal one", "tab 3 name contains a color or link code", function(p)
	p.windows[3].name = "a|||b"
end)
Rejects("a name with a line break", "tab 3 name contains a line break", function(p)
	p.windows[3].name = "tr\nade"
end)
Rejects("a name with a NUL byte", "tab 3 name contains a line break", function(p)
	p.windows[3].name = "tr\0ade"
end)
Rejects("a name with a byte that isn't UTF-8", "tab 3 name contains damaged text", function(p)
	p.windows[3].name = "tr\255ade"
end)
Rejects("a name with a character cut short", "tab 3 name contains damaged text", function(p)
	p.windows[3].name = "trade" .. HANGUL_SYLLABLE:sub(1, 2)
end)
Rejects("a channel name with a control character", "tab 1 channel name contains a line break", function(p)
	p.windows[1].channels[2].name = "My\tChannel"
end)

-- Rejected: message groups and channels

Rejects("a lowercase message group", "tab 1 has an invalid message group", function(p)
	p.windows[1].messageGroups[1] = "say"
end)
Rejects("a message group that is a number", "tab 1 has an invalid message group", function(p)
	p.windows[1].messageGroups[1] = 5
end)
Rejects("a hole in the message groups", "tab 1 message groups is not a list", function(p)
	p.windows[1].messageGroups = { [1] = "SAY", [3] = "GUILD", [4] = "PARTY" }
end)
Rejects("message groups with a text key", "tab 1 message groups is not a list", function(p)
	p.windows[1].messageGroups.extra = "SAY"
end)
Rejects("101 message groups", "too many entries in tab 1 message groups", function(p)
	for i = 1, 101 do
		p.windows[1].messageGroups[i] = "SAY"
	end
end)
Rejects("101 channels", "too many entries in tab 1 channels", function(p)
	for i = 1, 101 do
		p.windows[1].channels[i] = { name = "c" .. i, zoneChannelID = 0 }
	end
end)
Rejects("a channel that isn't a table", "tab 1 has an invalid channel", function(p)
	p.windows[1].channels[1] = "Trade"
end)
Rejects("a channel without an ID", "tab 1 has an invalid channel ID", function(p)
	p.windows[1].channels[1].zoneChannelID = nil
end)
Rejects("a negative channel ID", "tab 1 has an invalid channel ID", function(p)
	p.windows[1].channels[1].zoneChannelID = -1
end)
Rejects("an unknown channel field", "unknown field password in tab 1 channel", function(p)
	p.windows[1].channels[1].password = "x"
end)

-- Rejected: chat colors

Rejects("chat colors that aren't a table", "chat colors are not a table", function(p)
	p.colors = "red"
end)
Rejects("an unknown chat type", "unknown chat type NOT_A_TYPE", function(p)
	p.colors.NOT_A_TYPE = { r = 1, g = 1, b = 1 }
end)
Rejects("201 chat colors", "too many chat colors", function(p)
	p.colors = {}
	for i = 1, 201 do
		p.colors["TYPE" .. i] = { r = 0, g = 0, b = 0 }
	end
end)
Rejects("a chat color missing blue", "SAY color needs red, green and blue", function(p)
	p.colors.SAY.b = nil
end)
Rejects("class-colored names that are not a boolean", "GUILD class-colored names must be true or false", function(p)
	p.colors.GUILD.classColoredNames = "yes"
end)

-- Quoting untrusted text in a reason

local reason = Rejects("a field name with a color code and a line break", "unknown field", function(p)
	p.windows[1]["x|cffy\nz"] = true
end)
Check((reason or ""):find("unknown field xcffyz in", 1, true), "a quoted field kept its codes: " .. tostring(reason))

reason = Rejects("a long field name in another alphabet", "unknown field", function(p)
	p.windows[1]["a" .. HANGUL_SYLLABLE:rep(20)] = true
end)
-- Cut at 30 bytes: "a" and 9 whole characters, not part of a 10th.
local expectedCut = "unknown field a" .. HANGUL_SYLLABLE:rep(9) .. " in"
Check((reason or ""):find(expectedCut, 1, true), "a quoted field wasn't cut between characters: " .. tostring(reason))

return helpers.Failures()
