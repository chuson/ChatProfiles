# Contributing to ChatProfiles

Thanks for helping out. ChatProfiles is small on purpose, so most changes are a few lines in one file. This page covers how to get set up, how the code is organized, and what to check before you send a change.

If you're changing how the addon behaves, read `Chat Profiles Design Doc.md` first. It explains what the addon does and why.

## Getting set up

1. Copy or link the `ChatProfiles/` folder into your WoW Forever `Interface\AddOns` folder.
2. Open the repository in [VS Code](https://code.visualstudio.com/) and install the recommended extensions when it asks: the Lua language server, Ketho's WoW API, and StyLua. Together they flag unknown APIs and wrong arguments as you type, and format your code.
3. Optionally, install [Lua](https://www.lua.org/) 5.1 or later to run the tests yourself. GitHub runs them on every push and pull request either way.

## How the project is laid out

- `ChatProfiles/` is the addon itself, and the only folder that ships.
- `tests/` has tests that run outside the game.
- `.github/workflows/` runs luacheck and the tests on every push and pull request.

Each file in `ChatProfiles/` has one job:

| File | Does | Never |
| --- | --- | --- |
| `ChatSettings.lua` | Reads the live chat settings, compares them with a profile, applies a profile. | Prints, or touches saved data. |
| `ExportString.lua` | Builds export strings and checks imported ones. | Uses game APIs other than `C_EncodingUtil`, `Constants` and `ChatTypeInfo`, so the test can stand in for them outside the game. |
| `Profiles.lua` | Owns the saved data (`ChatProfilesDB`), the login apply and the logout save. | Builds UI. |
| `OptionsPanel.lua` | The options panel and `/chatprofiles`. | Changes chat settings or saved data itself; it goes through `Profiles`. |

Each file only uses the ones above it: `Profiles` uses `ChatSettings`, and `OptionsPanel` uses `Profiles` and `ExportString`.

## Chat terms

WoW's own code uses three words for chat windows, and we keep them apart:

- A **tab** is what the player sees and names, like "General" or "Trade".
- A **window** is one of the numbered slots behind the tabs, from 1 to 10. The `GetChatWindow*` functions take a window number.
- A **frame** is the UI object for a window, `ChatFrame1` to `ChatFrame10`. You pass it to the `FCF_*` functions and call methods like `frame:AddChannel` on it.

One exception: a profile stores its tabs in a list called `windows`, because that's the word the client's chat functions use.

## Code style

- Format with StyLua (`stylua.toml`). The recommended extension does it for you. luacheck (`.luacheckrc`) runs on GitHub.
- Indent with tabs. Name module functions in PascalCase (`ChatSettings.Read`), locals in camelCase, and constants in UPPER_CASE.
- Comments explain why, not what. Most lines don't need one. Do comment game behavior that a reader couldn't guess.
- Check inputs where they enter the addon (imports, game API results), not between our own functions.
- Keep it plain: no libraries, no `OnUpdate` polling, and no hooks on Blizzard functions.

## Using game APIs

The client is WoW Forever (interface 16001), which is closest to retail 12.1.5. APIs change between versions, so before using a new API:

1. Find the API in [Blizzard's UI source](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns), and make sure it isn't just a deprecated alias.
2. Confirm the client has the API. Print its name in game, for example `/run print(C_Timer.NewTimer)`. Anything other than `nil` means it exists. Events and UI templates can't be printed, so try those in game instead.
3. Add the API's global name to `read_globals` in `.luacheckrc`.

Use frame methods (`frame:AddMessageGroup`) rather than the old `ChatFrame_*` globals. Those only exist while the `loadDeprecationFallbacks` setting is on.

## Testing

- Run `lua tests/validate.lua` from the repository root. It checks the import validator against good and malformed profiles.
- Everything else needs the game. Section 11 of the design doc has the steps.

## Reviewing a change

Review one area at a time. A pass that looks at everything at once tends to stay at one level and miss the rest.

1. **Architecture:** which file does what, which way the dependencies run, and who owns each piece of state.
2. **Size:** functions that are too long or do several jobs, and helpers, tables or parameters that don't earn their place. Check how many places call each function: a helper used once usually belongs inline.
3. **Order:** each file and function reads from top to bottom.
4. **Naming:** one term for each idea, and names that match what the code does.
5. **Comments:** needed, accurate, and written in plain sentences.
6. **Correctness:** bugs, edge cases, and text that counts bytes where the player sees letters.
7. **Efficiency:** wasted work in code that runs often.

## Sending a change

Before you open a pull request:

- Format with StyLua, and run the validator test if you have Lua. GitHub runs it and luacheck on your pull request too.
- Try the change in game, including a `/reload` and a full logout, since saving happens at logout.
- If the change affects behavior, update the design doc to match.
- Keep each pull request to one change, and say in the description what you tested.

## Reporting a bug

Open an issue with:

- What you did, what you expected, and what happened instead.
- The client build, from `/run print(GetBuildInfo())`.
- Any Lua error text. Turn error popups on with `/console scriptErrors 1` if you don't see any.
- The status lines from the `/chatprofiles` panel, if they're relevant.
