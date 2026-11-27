# Contributing

ChatProfiles rewrites a player's chat every time they log in, so a broken change is very disruptive. Test every change well, both with the tests and in game. [docs/DESIGN.md](docs/DESIGN.md) explains how the addon works and why.

## Setup

- Copy or link `ChatProfiles/` into your WoW Forever `Interface\AddOns` folder.
- In VS Code, install the recommended extensions (Lua language server, Ketho's WoW API, StyLua). They catch unknown APIs and format on save.
- Install Lua 5.1 or later to run the tests. GitHub runs them and [luacheck](https://github.com/lunarmodules/luacheck) on every push and pull request. To run luacheck yourself, install it with `luarocks install luacheck` and run `luacheck .`.

## Layout

| File | Does | Never |
| --- | --- | --- |
| `ChatSettings.lua` | Reads the live chat settings, compares them with a profile, applies a profile. | Prints, or touches saved data. |
| `ExportString.lua` | Builds export strings and checks imported ones. | Uses game APIs other than `C_EncodingUtil`, `Constants` and `ChatTypeInfo`, so the tests can stand in for them. |
| `Profiles.lua` | Owns the saved data (`ChatProfilesDB`), the login apply and the logout save. | Builds UI. |
| `PanelText.lua` | The panel's status line, list of changes and export hint. | Builds frames. Keeping them out lets the tests check it. |
| `OptionsPanel.lua` | The options panel and slash commands. | Changes chat settings or saved data itself; it goes through `Profiles`. |

Each file only uses the ones above it.

WoW uses three words for chat windows, and the code keeps them apart: a **tab** is what the player sees and names, a **window** is a numbered slot from 1 to 10 (the `GetChatWindow*` functions), and a **frame** is the `ChatFrameN` object (the `FCF_*` functions and frame methods). Profiles store tabs in a list called `windows`, after the client's functions.

## Code

- Format with StyLua. Tabs for indentation, PascalCase for module functions, camelCase for locals, UPPER_CASE for constants.
- Comment only what the code can't say, usually game behavior a reader couldn't guess.
- Check data where it enters the addon (imports, game API results), not between our own functions.
- No libraries, no `OnUpdate` polling, no hooks on Blizzard functions.
- The client is interface 16001, closest to retail 12.1.5. Before using a new API, find it in [Blizzard's UI source](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns), check it exists in game with `/run print(TheFunction)`, and add it to `read_globals` in `.luacheckrc`. Use frame methods, not the old `ChatFrame_*` globals.

## Testing

Run `lua tests/run.lua` from the repository root, or `lua tests/run.lua tests/Profiles.lua` for one file. Each module has its own test file. Two more, `tests/Apply.lua` and `tests/WholePath.lua`, apply profiles to `tests/FakeChat.lua`, a working model of the client's chat windows and dock, and check that nothing differs afterward. The model copies Blizzard's `FloatingChatFrame.lua`, and its header lists what it copies. If the client changes how docking works, update the model first.

A rejection test also checks the reason, and every limit is tested from both sides.

The tests can't show that the client really behaves the way the stand-ins do. Before sending a change, try it in game with a `/reload`, a full logout and login, and a switch to another profile and back. Section 11 of the design doc lists the full checks.

### Recording the chat client

The `Read` tests replay what the game returned on a real character, in `tests/fixtures/ChatRecording.lua`. Record a new one after a client patch, or to cover a layout the current one doesn't have. The most useful layout has a docked tab that isn't selected, a locked and an unlocked undocked tab, a tab that was undocked and docked again, and a mix of zone and custom channels.

1. In game, run these three commands:

   ```
   /run local t={}for w=1,10 do t[w]={i={GetChatWindowInfo(w)},m={GetChatWindowMessages(w)},c={GetChatWindowChannels(w)}}end t.reserved=C_ChatInfo.GetNumReservedChatWindows() ChatProfilesDB.capture=t
   ```

   ```
   /run local c={}for k,v in pairs(getmetatable(ChatTypeInfo).__index)do if v.r then c[k]={v.r,v.g,v.b,v.colorNameByClass}end end ChatProfilesDB.capture.colors=c
   ```

   ```
   /run for w=1,10 do local t=ChatProfilesDB.capture[w] t.p={GetChatWindowSavedPosition(w)} t.s={GetChatWindowSavedDimensions(w)} end
   ```

2. `/reload`, then run `lua tests/record-fixture.lua <path to WTF\Account\NAME\SavedVariables\ChatProfiles.lua>`.
3. Run the tests. Where they fail, decide whether the client changed or the test assumed too much.
4. Clear the recording with `/run ChatProfilesDB.capture=nil` and another `/reload`.

## AI-assisted contributions

AI-assisted work is welcome, as long as it's disclosed: add a `Co-Authored-By:` line for the tool to each commit it helped with, as this repo's history does.

You're the author of anything you submit, however it was written. That means:

- You've read and understood every line, and you can explain it in review.
- Every game API it uses is real, current and present on the client. Follow the steps in [Code](#code) for each new one.
- You've tested the change in game, and it works as you describe it.
- The pull request description is yours: what changed, why, and what you tested.

## Sending a change

I'm happy to look at pull requests, though I can't promise to merge every one. For anything larger, it's worth opening an issue first so we can agree on the approach.

- Keep each pull request to one change, and say what you tested.
- Before sending it, read your own diff one area at a time: architecture, size, order, naming, comments, correctness, efficiency.
- If behavior changes, update the design doc to match.
