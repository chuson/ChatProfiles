# Contributing to ChatCopy

`ChatCopy Design Doc.md` explains what the addon does and why. Read it before changing behavior.

## Layout

- `ChatCopy/` is the addon itself. Copy or link it into the client's `Interface\AddOns` folder.
- `tests/` holds tests that run outside the game with plain Lua 5.1.
- `tools/` holds throwaway diagnostics, such as the login probe. Nothing in it ships.

## Files and their boundaries

| File | Does | Never |
| --- | --- | --- |
| `Chat.lua` | Reads the live chat setup, diffs it against a profile, applies a profile. | Prints, or touches saved data. |
| `Codec.lua` | Export strings, and validation of imported ones. | Calls game APIs other than `C_EncodingUtil`, so it can be tested outside the game. |
| `Profiles.lua` | Owns `ChatCopyDB`, the login apply and the logout save. | Builds UI. |
| `UI.lua` | The options panel and `/chatcopy`. | Changes chat or saved data directly; it goes through `Profiles`. |

Dependencies only point down this table: `UI` uses `Profiles` and `Codec`, and `Profiles` uses `Chat`.

## Style

- Format with [StyLua](https://github.com/JohnnyMorganz/StyLua) (`stylua.toml`) and lint with [luacheck](https://github.com/lunarmodules/luacheck) (`.luacheckrc`).
- Tabs for indentation. Module functions in PascalCase (`Chat.Read`), locals in camelCase, constants in UPPER_CASE.
- Comments say why, not what. Most lines need none.
- Check inputs where they enter the addon (imports, game API results), not between our own functions.
- Keep it plain: no libraries, no `OnUpdate` polling, no hooks on Blizzard functions.

## Game APIs

The client is WoW Forever (interface 16001), closest to retail 12.1.5. APIs change between versions, so before using a new one:

1. Find it in [Blizzard's UI source](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns), and check it is not only a deprecated alias.
2. Check it exists in game, for example `/run print(SomeFunction)`.
3. Add it to `read_globals` in `.luacheckrc`.

Use chat frame methods (`frame:AddMessageGroup`) rather than the old `ChatFrame_*` globals, which only exist while the `loadDeprecationFallbacks` setting is on.

## Testing

- `lua tests/validate.lua` runs the import validator against good and malformed profiles.
- Everything else is tested in game; section 11 of the design doc has the steps.
