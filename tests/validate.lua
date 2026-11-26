-- Checks imports: how pasted text is read, and the validator against good and malformed profiles.
-- Run from the repository root with Lua 5.1 or later: lua tests/validate.lua

-- Stand-ins for the game globals that ExportString reads. The decoders only record what
-- they were given, since the test checks what Import passes them, not Base64 or CBOR.
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
ChatTypeInfo = { SAY = {}, GUILD = {}, CHANNEL1 = {} }
local decodedText
C_EncodingUtil = {
	DecodeBase64 = function(text)
		decodedText = text
		return text
	end,
	DeserializeCBOR = function()
		return { categories = {}, windows = {} }
	end,
}

local ns = {}
assert(loadfile("ChatProfiles/ExportString.lua"))("ChatProfiles", ns)
local Validate, Import = ns.ExportString.Validate, ns.ExportString.Import

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

local failures = 0

local function Expect(description, shouldPass, change)
	local data = GoodProfile()
	if change then
		data = change(data) or data
	end
	local result, reason = Validate(data)
	if (result ~= nil) ~= shouldPass then
		failures = failures + 1
		print("FAIL: " .. description .. (reason and (" (" .. reason .. ")") or ""))
	end
	return result, reason
end

local function Accepts(description, change)
	return (Expect(description, true, change))
end

-- Returns the reason given.
local function Rejects(description, change)
	local _, reason = Expect(description, false, change)
	return reason
end

local function Fail(message)
	failures = failures + 1
	print("FAIL: " .. message)
end

-- Reading pasted text
Import("  ChatProfiles1:ab\r\ncd ef\n")
if decodedText ~= "abcdef" then
	Fail("line breaks and spaces inside a pasted export were not removed: " .. tostring(decodedText))
end

-- Accepted
Accepts("a complete profile")
Accepts("a profile without colors", function(p)
	p.colors = nil
end)
Accepts("a tab with only a key and name", function(p)
	p.windows = { { key = "name:x", name = "x" } }
end)
local unusualName = "a||b " .. HANGUL_SYLLABLE
local kept = Accepts("names with a literal | and letters outside English", function(p)
	p.windows[3].name = unusualName
	p.windows[3].key = "name:anything"
	p.windows[1].channels[2].name = HANGUL_SYLLABLE
end)
if kept and (kept.windows[3].name ~= unusualName or kept.windows[3].key ~= "name:" .. unusualName) then
	Fail("a name was changed on import, or the key wasn't built from it")
end

-- Rejected
Rejects("not a table", function()
	return "ChatProfiles"
end)
Rejects("an unknown top-level field", function(p)
	p.extra = true
end)
Rejects("missing categories", function(p)
	p.categories = nil
end)
Rejects("an unknown category", function(p)
	p.categories.bogus = true
end)
Rejects("a category that is not a boolean", function(p)
	p.categories.tabs = 1
end)
Rejects("missing tabs", function(p)
	p.windows = nil
end)
Rejects("tabs that are not a list", function(p)
	p.windows = { first = p.windows[1] }
end)
Rejects("a hole in the tab list", function(p)
	p.windows[2] = nil
end)
Rejects("too many tabs", function(p)
	for i = 4, 11 do
		p.windows[i] = { key = "name:t" .. i, name = "t" .. i }
	end
end)
Rejects("two tabs with the same name", function(p)
	p.windows[4] = { key = "name:trade", name = "trade" }
end)
Rejects("an unknown tab field", function(p)
	p.windows[1].script = "print(1)"
end)
Rejects("a bad key", function(p)
	p.windows[1].key = "window:3"
end)
Rejects("a name with a color code", function(p)
	p.windows[3].name = "tr|cffff0000ade"
end)
Rejects("a name with a single | after a literal one", function(p)
	p.windows[3].name = "a|||b"
end)
Rejects("a name with a line break", function(p)
	p.windows[3].name = "tr\nade"
end)
Rejects("a name with a NUL byte", function(p)
	p.windows[3].name = "tr\0ade"
end)
Rejects("a name with a byte that isn't UTF-8", function(p)
	p.windows[3].name = "tr\255ade"
end)
Rejects("a name with a letter cut short", function(p)
	p.windows[3].name = "trade" .. HANGUL_SYLLABLE:sub(1, 2)
end)
Rejects("a channel name with a control character", function(p)
	p.windows[1].channels[2].name = "My\tChannel"
end)
local reason = Rejects("an unknown field with a long name in another alphabet", function(p)
	p.windows[1]["a" .. HANGUL_SYLLABLE:rep(20)] = true
end)
-- The quoted field is cut at 30 bytes: "a" and 9 whole characters, not part of a 10th.
if not (reason or ""):find("unknown field a" .. HANGUL_SYLLABLE:rep(9) .. " in", 1, true) then
	Fail("a quoted field name wasn't cut between letters: " .. tostring(reason))
end
Rejects("a name that is too long", function(p)
	p.windows[3].name = string.rep("a", 201)
end)
Rejects("a fractional font size", function(p)
	p.windows[1].fontSize = 12.5
end)
Rejects("a huge font size", function(p)
	p.windows[1].fontSize = 400
end)
Rejects("a color above 1", function(p)
	p.windows[1].r = 1.5
end)
Rejects("a negative opacity", function(p)
	p.windows[1].a = -0.1
end)
Rejects("a color given as text", function(p)
	p.windows[1].g = "0"
end)
Rejects("only part of a color", function(p)
	p.windows[2].r = 0.5
end)
Rejects("a lock that is not a boolean", function(p)
	p.windows[1].locked = 1
end)
Rejects("a lowercase message group", function(p)
	p.windows[1].messageGroups[1] = "say"
end)
Rejects("a message group that is a number", function(p)
	p.windows[1].messageGroups[1] = 5
end)
Rejects("a gap in the message groups", function(p)
	p.windows[1].messageGroups = { [1] = "SAY", [3] = "GUILD", [4] = "PARTY" }
end)
Rejects("message groups with a text key", function(p)
	p.windows[1].messageGroups.extra = "SAY"
end)
Rejects("too many message groups", function(p)
	for i = 1, 101 do
		p.windows[1].messageGroups[i] = "SAY"
	end
end)
Rejects("a channel without an ID", function(p)
	p.windows[1].channels[1].zoneChannelID = nil
end)
Rejects("a negative channel ID", function(p)
	p.windows[1].channels[1].zoneChannelID = -1
end)
Rejects("an unknown channel field", function(p)
	p.windows[1].channels[1].password = "x"
end)
Rejects("an unknown chat type", function(p)
	p.colors.NOT_A_TYPE = { r = 1, g = 1, b = 1 }
end)
Rejects("a chat color missing blue", function(p)
	p.colors.SAY.b = nil
end)
Rejects("class-colored names that are not a boolean", function(p)
	p.colors.GUILD.classColoredNames = "yes"
end)

if failures == 0 then
	print("All validator checks passed.")
else
	print(failures .. " validator check(s) failed.")
	os.exit(1)
end
