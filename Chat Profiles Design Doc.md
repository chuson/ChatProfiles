# Chat Profiles: Design Doc

Status: draft for review, revised after engineering and addon-community review, then checked against Blizzard's UI source and in-game probes. Target client: WoW Forever 1.60.1 (build 71037, interface 16001), whose UI code most closely matches retail 12.1.5. Scope: profiles of chat settings that characters use, with changes saved automatically and shared across every character using the same profile, plus import and export.

## 1. Problem

Chat window setup (tabs, message groups, per-tab channels, appearance) is configured per character, so every new alt starts from defaults. The client has no "copy from character" feature. Hand-copying `chat-cache.txt` between character folders is the folk workaround, but it needs the game closed and depends on server-sync behavior we cannot verify. Chat Profiles does the transfer in-game through the chat APIs.

## 2. Goals and non-goals

**Goals**

- Named profiles captured from, and applied to, the live chat setup.
- A character uses one profile at a time. Chat changes made on it are saved into the profile automatically at logout, or at once with **Save now**, and every other character using that profile receives them at its next login.
- Move a setup between characters on one account by selecting the profile on each, and between users via an export string.
- Small codebase, no libraries, no polling, no hooks on Blizzard functions. Readability comes before line count.

**Non-goals (v1)**

- Channel *membership* (joining or leaving). We only manage which channels each tab displays.
- Combat log filters. `Blizzard_CombatLog` saves them account-wide, so they already follow every character (open question 8).
- Frame position and size (Edit Mode) and reordering existing tabs.
- Chat behavior settings (chat style, whisper mode, timestamps, chat bubbles, mouse-wheel scroll). They are stored per account (section 3), so they already follow every character.
- A default profile for new characters. Deferred.
- Undo. Users can export a profile to keep a version.

## 3. API surface

Observed on the live client, and checked against Blizzard's 12.1.5 UI source (section 12):

| Purpose | API | Notes |
| --- | --- | --- |
| Read window | `GetChatWindowInfo(i)` | name, size, r, g, b, a, shown, locked, docked, uninteractable. `docked` is nil only for a floating window. `shown` is current visibility, so docked tabs that are not selected report false. |
| Read groups | `GetChatWindowMessages(i)` | varargs of group names |
| Read channels | `GetChatWindowChannels(i)` | name, zoneChannelID pairs. Returns channels the window is *configured to show*, not membership. A fresh character's window 1 lists the full default set (open question 11). |
| Groups | `frame:AddMessageGroup(group)` / `frame:RemoveMessageGroup(group)` | The `ChatFrame_*` globals are deprecated aliases of these methods and exist only while the `loadDeprecationFallbacks` CVar is on. It is on here, but we don't rely on it. |
| Channels | `frame:AddChannel(name)` / `frame:RemoveChannel(name)`, `C_ChatInfo.GetChannelShortcutForChannelID(id)` | `ChatFrame_AddChannel` has no alias. Round trip verified on window 1. The shortcut call turns a zone channel ID into the channel's local name. |
| Windows | `FCF_OpenNewWindow(name, noDefaultChannels)`, `FCF_CanOpenNewWindow()`, `FCF_SetWindowName`, `FCF_Close(frame)` | `FCF_OpenNewWindow` returns `frame, index`, or nothing when every slot is in use. Unless `noDefaultChannels` is set, it adds SAY, YELL, GUILD, WHISPER, BN_WHISPER, PARTY, PARTY_LEADER and CHANNEL. It docks and unlocks the new window. It does not dedupe by name (forum report), so look up by name before creating. `FCF_Close` undocks and hides the window and clears its groups and channels. |
| Appearance | `FCF_SetChatWindowFontSize(nil, frame, size)`, `FCF_SetWindowColor`, `FCF_SetWindowAlpha`, `FCF_SetLocked(frame, isLocked)` | Signatures confirmed in source. `FCF_SetLocked` passes its value straight to `SetChatWindowLocked`, and Blizzard passes booleans. Color and alpha take a trailing `doNotSave`, which we leave nil. The phase-1 prototype applied appearance correctly in a live test. |
| Chat colors | `ChatTypeInfo[type]` (`r`, `g`, `b`, `colorNameByClass`), `ChangeChatColor`, `SetChatColorNameByClass` | Both setters exist on the client. Their signatures, `ChangeChatColor(type, r, g, b)` and `SetChatColorNameByClass(type, enabled)`, come from older API docs and are not in the 12.1.5 generated docs, so the post-apply diff confirms them. `CHANNEL1` to `CHANNEL20` colors follow the character's local channel numbers. |
| Limits and names | `Constants.ChatFrameConstants.MaxChatWindows`, `C_ChatInfo.GetNumReservedChatWindows()`, `ChatTypeGroup` | 10 windows, of which 3 are reserved. `NUM_CHAT_WINDOWS` is a deprecated alias. `ChatTypeGroup` keys are the valid message group names (47 on 12.1.5). |

Window numbers are not tab positions. Windows 1 to 3 are reserved (`C_ChatInfo.GetNumReservedChatWindows()` returns 3): General, Combat Log, and a Voice transcription window. The Voice window is not shown and not docked, but it still occupies a number, and `FCF_OpenNewWindow` never reuses it. Custom tabs start at 4. A window counts as *active* when `docked ~= nil` or `shown`. Docked tabs report `shown = false` while another tab is selected, so `shown` alone is not enough, and `docked` is nil only for floating windows.

CVars: `synchronizeChatFrames = 1`, `synchronizeConfig = 1` (Blizzard's own sync stays on). `synchronizeSettings` and `synchronizeMacros` read `nil`. `loadDeprecationFallbacks = 1`.

The chat behavior CVars `chatStyle`, `whisperMode`, `showTimestamps`, `chatBubbles` and `chatMouseScroll` are stored per account and not per character (`C_CVar.GetCVarInfo` on the live client), so they already follow every character. `chatClassColorOverride` is stored in the local config, neither per account nor per character on the server.

**Confirmed in source and present on the client** (section 12): Settings panel registration and `C_EncodingUtil`. **To confirm in game** (section 10): the chat color setter signatures.

Each character's `WTF\Account\<account>\<realm>\<character>\chat-cache.txt` is the client's copy of that character's chat setup. It has a `COLORS` section with every chat type's color, and a `WINDOW` block per window with its message groups, custom channels by name, and zone channels as a `ZONECHANNELS` bitmask in which bit n is zone channel ID n+1. Chat Profiles never reads the file; it shows what the client stores per character.

## 4. Data model

```lua
ChatProfilesDB = {
  schema = 1,
  profiles = {
    ["Main"] = {
      categories = { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true },
      windows = { ... },
      colors = { ... },
    },
  },
  profileByCharacter = { ["Name-Realm"] = "Main" },   -- the profile each character uses
}
```

A window entry: `key` (`"window:1"`, `"window:2"`, or `"name:<tab name>"` for custom tabs), `name`, `fontSize`, `r`, `g`, `b`, `a`, `locked`, a sorted array `messageGroups`, and an array `channels` of `{ name, zoneChannelID }` sorted by name. The list holds tabs, but it's called `windows` because that's the client's word. A field added later needs no migration, because an older profile that lacks it simply leaves that setting alone. A profile's `colors` maps each `ChatTypeInfo` key to `r`, `g`, `b` and `classColoredNames`.

- Profiles are keyed by name. The `profileByCharacter` table is account-wide, so rename updates every reference in one loop, and delete detaches the characters that used the profile.
- A profile holds only its current setup: no version number and no history. Whether a character is in sync is answered by diffing its live chat against the profile.
- A renamed or transferred character looks unassigned under its new `Name-Realm` key. This is harmless: the user selects a profile again.
- Saved variables are initialized in `ADDON_LOADED` for Chat Profiles (they are not available at file scope): defaults are filled in. `schema` is stored so a later format change can be detected, but no migration code is written until a second schema exists. A new table is assigned to the global `ChatProfilesDB`, not only to the namespace, or the client has nothing to write. The event is then unregistered. Chat state is never read at this point: on a fresh login it still predates the client's settings download (open question 1).
- Windows 1 and 2 are matched by number. Custom tabs are matched by name and created if missing. Duplicate names are ignored with a warning.
- Inactive windows (the Voice window) are ignored. Combat Log receives appearance settings only, and its groups and channels are never touched.
- With the Tabs category on, apply makes the set of active custom windows equal to the profile: it creates missing tabs and closes the ones the profile does not contain. Windows 1 and 2 are never closed. Renames and deletions therefore carry to every character. With it off, apply only updates tabs that already exist by name.
- A font size of `0` means no size was ever saved, and the window keeps its default font. `Diff` and `Apply` skip a size of 0 on either side (open question 6).
- A channel with a `zoneChannelID` above 0 is matched by ID, and on apply its name comes from `C_ChatInfo.GetChannelShortcutForChannelID`, so it carries across locales. A channel with `zoneChannelID` 0 is matched by name.

### Setting categories

Each profile stores which categories it manages (`categories`). An unselected category is neither applied nor saved, so the character, or another addon, keeps control of it.

| Category | Settings | Default | Notes |
| --- | --- | --- | --- |
| Tabs | which custom tabs exist, and their names | on | Off: apply never creates or closes tabs, and only updates tabs that already exist by name. |
| Messages and channels | message groups and channels shown in each tab | on | The core of the addon. Combat Log groups and channels are never touched. |
| Font and background | font size, background color and opacity, locked | on | Applied through the setter table in section 5. |
| Chat colors | color per chat type, channel colors, class-colored names | on | Stored per character (open question 10). Channel colors follow local channel numbers (section 9). |

Outside every category: chat behavior settings and combat log filters, which are account-wide (section 3, open question 8); tab position, size and order (Edit Mode).

## 5. Architecture

Four small files, one shared namespace (`local _, ns = ...`), dependencies in one direction. The addon registers three events: `ADDON_LOADED`, to initialize saved variables and the options panel; `PLAYER_LOGIN`, to apply the character's profile when live chat differs from it; and `PLAYER_LOGOUT`, to save the selected profile. `ADDON_LOADED` and `PLAYER_LOGIN` are unregistered after they fire, since `/reload` registers them again.

| File | Responsibility | Depends on |
| --- | --- | --- |
| `ChatSettings.lua` | Pure engine: read live state, diff against a profile, apply. Returns results, never prints, never touches saved data. | WoW chat APIs |
| `Profiles.lua` | Create, rename, delete; select a profile for the current character; apply it at login when live chat differs; save live chat into it (including at logout). Owns `ChatProfilesDB`. | `ChatSettings` |
| `ExportString.lua` | Profile to export string and back, including validation of imported data. Pure, so it can be tested alone. | none |
| `OptionsPanel.lua` | Settings panel. Calls `Profiles` and `ExportString`, and displays results. | `Profiles`, `ExportString` |

### Engine API

```lua
ChatSettings.Read(categories)       -- -> live settings
ChatSettings.Diff(live, profile)    -- -> { {text=, apply=, opensOrClosesTab=}, ... }   (empty = in sync)
ChatSettings.Apply(profile)         -- -> remaining differences   (empty = success)
```

Design points:

- One diff drives everything. The panel's status line and the post-apply verification both call `Diff` and test for an empty list.
- `Read` returns only active windows (`docked ~= nil` or `shown`). This replaces special-casing window 3 and matching the localized name "Voice".
- Each change is a closure over a window number and resolves `_G["ChatFrame" .. windowNumber]` at run time. No frame objects are stored.
- The engine calls frame methods, never the deprecated `ChatFrame_*` globals.
- Appearance fields live in a table of `{field, setter}` pairs. Groups and channels share one set-difference helper.
- Each change runs under its own `pcall`. One bad call does not abort the rest. Apply ends by re-reading and returns what still differs, so a thrown error and a silent no-op are reported the same way.
- `Apply` is two passes. Pass 1 creates missing windows in dock order with `FCF_OpenNewWindow(name, true)`, only when no window with that name exists, then the state is re-read. If no slot is free, the window is not created, and it stays in the remaining diff. Pass 2 runs the re-computed diff.
- `Diff` also reports active custom windows that the profile lacks, and `Apply` closes them with `FCF_Close` (open question 4).
- `Read` and `Diff` skip categories the profile does not include, so one switch stops both applying and saving that category.
- Constants are named (`GENERAL_WINDOW = 1`, `COMBAT_LOG_WINDOW = 2`, `MAX_WINDOWS = Constants.ChatFrameConstants.MaxChatWindows`). The first custom window is `C_ChatInfo.GetNumReservedChatWindows() + 1`.

## 6. Selecting, saving and syncing

A character uses at most one profile. Selecting a profile applies it, and while it stays selected the character's chat changes are saved into it automatically. Characters that use the same profile converge: a change saved by one is applied on the others at their next login.

| Trigger | Condition | Action |
| --- | --- | --- |
| Login (`PLAYER_LOGIN`) | uses a profile and live chat differs | apply the profile, verify, and on failure stop saving this session |
| Select a profile | always | save into the old profile, then apply the new one |
| Save as new profile | always | live chat becomes a new profile, and this character uses it |
| Save now (panel button) | uses a profile, live chat differs, session not failed | save live chat into the profile immediately |
| Logout (`PLAYER_LOGOUT`) | uses a profile, live chat differs, session not failed | save live chat into the profile |

- **Login** (`PLAYER_LOGIN`, which also fires on `/reload`): if the character uses a profile and `Diff(Read(), profile)` is non-empty, run `ChatSettings.Apply(profile)` and `Diff` again. If the diff is now empty, done. If not, mark the session failed. The profile wins at login. It runs one frame after the event (`C_Timer.After(0)`), which in practice falls after the loading screen, so other addons' login handlers, such as chat history restore, finish first. The probe measured that the client's downloaded chat settings arrive before `PLAYER_LOGIN` and nothing changes afterward (open question 1), so there is no retry and no fixed delay.
- **Select** (panel dropdown): first save the current chat into the previously selected profile, if any, then run `ChatSettings.Apply(profile)` and `ChatSettings.Diff` again to list anything that did not take. **None** saves into the old profile and detaches the character.
- **Save** is `Profiles.SaveSelected()`: if `Diff(Read(), profile)` is non-empty, replace the profile's windows with `ChatSettings.Read()`. It runs at `PLAYER_LOGOUT`, when the user presses **Save now**, and just before a new profile is applied. `PLAYER_LOGOUT` fires on both logout and `/reload`, the chat APIs still return the live setup when it fires (open question 2), and it is the last event before saved variables are written. The client writes them only at logout or `/reload`, so the logout save alone loses nothing. Save now is for seeing and exporting a change before logging out.
- **No version numbers.** Login and logout use the same comparison with opposite winners: the profile wins at login, and the character wins at logout, so a character that changed its chat has always saved before the next login. The one case this cannot distinguish is a session that ended without its logout save (a crash, or the guard below). The next login then restores the profile, and that session's tweaks are lost. This matches the accepted crash risk in section 9.
- **Apply guard.** If an apply (at login or on select) still leaves differences, the session is marked failed and every save is skipped for the rest of the session, including the save-first step of a profile switch. A half-applied state must not overwrite the profile, because the profile is shared with other characters. The status line says so, because a profile that never applies cleanly would otherwise stop this character saving without any sign.
- Chat Profiles neither relies on nor changes the client's own chat upload (`synchronizeChatFrames = 1`).

### Compatibility with other chat addons

- Apply runs only when live chat differs from the profile, so a routine login or `/reload` changes nothing.
- Chat Profiles reads and writes chat configuration only. It never reads, clears or re-adds chat lines, so 12.x secret messages never pass through it, and it hooks no Blizzard functions.
- Existing windows are updated in place and keep their window number. History addons that appear to key saved chat by window index, such as Leatrix Plus "Restore chat messages", keep each tab's history with the right tab.
- The login apply waits one frame after `PLAYER_LOGIN`, so other addons' login handlers, including chat history restore, run first.
- Closing a tab is the one destructive step: it discards that tab's scrollback, including any restored history. It only happens with the Tabs category on, when the profile lacks the tab.
- If another addon also sets up chat at login, the two would conflict on every login, and the logout save would capture the other addon's result. The status line shows the differences, and unchecking the category that addon manages resolves it.

## 7. Import and export

- Format: `ChatProfiles1:<payload>`, where the prefix versions the format.
- Payload: `C_EncodingUtil.SerializeCBOR`, then `EncodeBase64` (both documented, added in 11.1.5). There is no compression. Profiles are a few KB, and `DecompressString` has no caller-set size limit (a hard cap of about 100 MB), so a small crafted string could force a large allocation.
- Deterministic output is not required, since nothing hashes or compares strings. `SerializeCBOR` does not sort map keys.
- **Strings are data, never code.** Check the input length against a fixed cap first (for example 64 KB). Then decode under `pcall` (Base64, then CBOR, which errors past 100 nesting levels and rejects tags), and validate against a whitelist before anything is stored:
  - known fields only, with type checks
  - colors and alpha between 0 and 1
  - font size either 0 or within a sane range (bounds to be confirmed)
  - hard caps on window count (`MAX_WINDOWS`), name length, and group and channel counts
  - the `|` character stripped from profile, tab and channel names, since they reach the UI and `|c`, `|H` and `|T` are display escape sequences
  - group names checked against the keys of `ChatTypeGroup`, and color names against the keys of `ChatTypeInfo`
- A string that fails a check is rejected with the reason shown. Values are never clamped into range, so an import either matches what was exported or is not added. Stripping `|` from names is the one exception, since it only removes display escapes.
- Import only adds a profile to the list. Applying is a separate act.
- Channels with a zone channel ID are matched by ID (section 4), so they import across locales. Channels without one are matched by name.

## 8. UI

A canvas category under **Esc > Options > AddOns > Chat Profiles**, also opened by `/chatprofiles`. No other slash commands. It is registered with `Settings.RegisterCanvasLayoutCategory(frame, name)` and opened with `Settings.OpenToCategory(category:GetID())`. The older pattern of opening by name is reported broken on current clients.

```
Profile:  [ Main            v ]     None / Main / Raid
Any changes you make to your chat settings are saved to this profile when you log out.
Includes:  [x] Tabs  [x] Messages and channels  [x] Font and background  [x] Chat colors

[Save as new profile]  [Rename]  [Delete]

Your chat settings match the profile.  |  N unsaved changes. They'll be saved when you log out.  |  Some settings couldn't be applied, ...

[Save now]  [Export]  [Import]
[ text box: ChatProfiles1:... ]
Import as: [________]  [Add profile]
```

Behavior:

- The panel frame is registered at load, and its widgets are built on first show.
- Selecting a profile applies it, after saving the current chat into the previously selected profile, so no tweaks are lost on a switch.
- **Save as new profile** forks: the live setup becomes a new profile and this character uses it. The previous profile is left as it was, which is why a fork does not run the save-first step.
- Chat settings change only through selecting a profile or the game's own chat UI. Import adds a profile to the list and nothing else.
- Status is `Diff(Read(), selected profile)`, run when the panel opens and after a change.
- **Save now** runs the same save as logout, immediately. It updates the profile in memory, so the status line and Export reflect the change at once; the client still writes it to disk at the next logout or `/reload`. It is disabled while the session is marked failed.
- The category checkboxes belong to the profile, so every character using it manages the same categories, and export strings carry the selection.

## 9. Risks and accepted trade-offs

- No undo. Selecting a profile on a character that uses none overwrites its setup with nothing saved first. Mitigation: use Save as new profile, or export, before the first apply.
- A tweak on one character is saved into the shared profile and applied on every character that uses it at its next login. Two characters using the same profile: last logout wins. Accepted.
- A failed apply (at login or on select) skips the logout save (section 6), so partial failures cannot spread through a shared profile.
- The login apply relies on the client's chat settings being final by `PLAYER_LOGIN`, which the probe measured on one character (open question 1). The post-apply verify and the apply guard catch a late overwrite if one happens.
- Chat APIs may change between 12.x patches. The engine isolates them in one file, and the post-apply `Diff` surfaces silent no-ops as remaining differences.
- A session that ends without its logout save (a crash, or a skipped save after a failed apply) loses that session's chat changes. Saved variables are written at logout, reload or clean exit, and the profile wins at the next login.
- Imported strings are untrusted input. Validation (section 7) is the control.
- With every window slot in use, `FCF_OpenNewWindow` creates nothing, and the missing tab appears in the remaining diff.
- Closing a tab discards its scrollback, including history restored by another addon. It only happens when the Tabs category is on and the profile lacks the tab.
- Channel colors are stored per channel number (`CHANNEL1` to `CHANNEL20`), and two characters may number the same channel differently, for example when one has joined an extra channel. The color then lands on whichever channel holds that number. Accepted for v1.
- Another addon that rebuilds chat at login would conflict with Chat Profiles on every login. Mitigation: uncheck the category that addon manages.

## 10. Open questions

Answers come from Blizzard's 12.1.5 UI source (section 12), from in-game checks, including a temporary probe addon, and from the client's own saved files. Answered questions keep their numbers so earlier references still hold.

**Answered**

1. **Login apply.** On a fresh login the chat setup changes on `UPDATE_CHAT_WINDOWS` twice, the second time just after `VARIABLES_LOADED` (the server download, about 5 seconds in). From `PLAYER_LOGIN` on it stays unchanged through 15 seconds after `PLAYER_ENTERING_WORLD`. On `/reload` it is already final when `ADDON_LOADED` fires. Event order on both: `VARIABLES_LOADED`, `PLAYER_LOGIN`, `SETTINGS_LOADED`, `PLAYER_ENTERING_WORLD`. Apply at `PLAYER_LOGIN` with no retry; never read chat at `ADDON_LOADED`.
2. **Logout save.** `PLAYER_LOGOUT` fires on both logout and `/reload`, and the chat APIs return the same setup as during play. No fallback save is needed.
3. **Window creation.** `FCF_OpenNewWindow` takes the first slot after the reserved ones (3 on this client) that is neither shown nor docked, so the Voice window is never reused. It adds eight default groups unless `noDefaultChannels` is set, docks and unlocks the window, and returns nothing when all slots are in use.
4. **Closing windows.** `FCF_Close(frame)` undocks and hides the window and clears its groups and channels. Hiding clears the window's shown flag through its `OnHide` script, which frees the slot for `FCF_OpenNewWindow`. A minimized window keeps the flag.
5. **Locked flag.** `FCF_SetLocked` passes its value straight to `SetChatWindowLocked`, and Blizzard passes booleans.
6. **Font size `0`.** No size was ever saved; the window keeps its default font, and Blizzard's own code skips setting the font for 0. `Diff` and `Apply` skip it (section 4).
7. **Tab order.** `FCF_DockFrame` returns early for an already-docked frame, so it cannot reorder tabs. Tab order stays a non-goal.
8. **Combat log.** `Blizzard_CombatLog.toc` lists `Blizzard_CombatLog_Filters` under `SavedVariables`, not `SavedVariablesPerCharacter`, so filters are account-wide and already follow every character. Confirmed on this client: `Blizzard_CombatLog.lua` is in the account-level `SavedVariables` folder, not in any character folder.
9. **Group and channel names.** Group names are the keys of `ChatTypeGroup`. Channel names are localized shortcuts, but `GetChatWindowChannels` also returns a zone channel ID, which `C_ChatInfo.GetChannelShortcutForChannelID` turns back into the local name, so channels are stored with both (section 4). The client does the same: `chat-cache.txt` saves each window's zone channels by ID (section 3). Confirmed in game: `C_ChatInfo.GetChannelShortcutForChannelID(47)` returns `OOC`.
10. **Chat colors.** Stored per character. Every character's own `chat-cache.txt` holds a `COLORS` section with each chat type's color and a per-type flag that is most likely class-colored names. The Chat colors category is on by default.
11. **Default channels on window 1.** The probe character had moved General (1), Trade (2), LocalDefense (22) and channel 46 into its own "trade" tab, so its window 1 showed only IDs 32 to 36 and 47. A character with an untouched setup shows all of them on window 1: 1, 2, 22, 32 to 36, 42, 46 and 47. Decoding the `ZONECHANNELS` bitmask in each character's `chat-cache.txt` gives exactly the list `GetChatWindowChannels` returned in game.

**To confirm in game**

- `ChangeChatColor` and `SetChatColorNameByClass` take the signatures in section 3. The first live apply with Chat colors on shows any mismatch as a remaining difference.

## 11. Build and test plan

0. **Repository.** `git init`; `ChatProfiles.toc` with `## Interface: 16001` and `## SavedVariables: ChatProfilesDB`; `.luacheckrc` listing the WoW globals in use; a StyLua config; `CONTRIBUTING.md` with the file boundaries from section 5 and the code style rules; `tests/validate.lua`, runnable with plain Lua 5.1.
1. **Engine.** `ChatSettings.lua` with the API above. Verified live (step 5); the post-apply `Diff` reports anything that did not take.
2. **Profiles.** Storage, select with save-first, login apply with verify and the failure guard, logout save, Save now, category selection, rename and delete updating `profileByCharacter`, and saved-variable initialization.
3. **Import and export.** `ExportString.lua` and its validator. The validator is plain Lua and gets one test file (`tests/validate.lua`) covering wrong types, oversized fields, unknown keys and `|` escapes. Invalid Base64, deep nesting and oversized input are checked in game.
4. **UI.** Panel over the existing `Profiles` and `ExportString`.
5. **Live tests, logout save and login apply first.** Change a tab on a character that uses a profile, log out, log in, and confirm the profile holds it. Repeat with `/reload`. Log into a second character using the same profile and confirm it matches, then log in again and confirm the login apply finds nothing to change. Switch profiles and confirm the old one kept the tweaks. Then: apply on a fresh character and confirm no differences remain, rename and delete a tab on one character and confirm both carry to a second, and apply with every window slot in use.
6. **Compatibility.** With Leatrix Plus "Restore chat messages" on: `/reload` with nothing to apply and confirm history survives in every tab, then apply a profile that changes groups and one that adds a tab, and confirm the existing tabs keep their history. Also confirm Save now updates the status line and Export at once.
7. **Later modules.** A new-character default, tab order, and frame position and size.

## 12. References

- [Blizzard UI source, 12.1.5.70961](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns): `Blizzard_ChatFrameBase` (chat frame methods, `FloatingChatFrame.lua` and `.xml`, `ChatTypeInfoConstants.lua`), `Blizzard_DeprecatedChatInfo` (the `ChatFrame_*` aliases), `Blizzard_CombatLog` (filter storage), `Blizzard_Settings_Shared`, and `Blizzard_APIDocumentationGenerated` (`C_EncodingUtil`, `C_ChatInfo`, chat constants).
- [GetChatWindowInfo](https://warcraft.wiki.gg/wiki/API:GetChatWindowInfo): return values, including `docked` nil for floating windows.
- [Settings API](https://warcraft.wiki.gg/wiki/Settings_API) and [Settings.OpenToCategory](https://warcraft.wiki.gg/wiki/API:Settings.OpenToCategory): canvas registration and ID-based opening.
- [SerializeCBOR](https://warcraft.wiki.gg/wiki/API:C_EncodingUtil.SerializeCBOR), [DeserializeCBOR](https://warcraft.wiki.gg/wiki/API:C_EncodingUtil.DeserializeCBOR) and [DecompressString](https://warcraft.wiki.gg/wiki/API:C_EncodingUtil.DecompressString): serialization limits and the decompression cap.
- [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions): when saved variables load and are written.
- [Blizzard forums: adding a chat tab through code](https://us.forums.blizzard.com/en/wow/t/trouble-confusion-on-adding-a-chat-tab-through-code/185148): `FCF_OpenNewWindow` does not dedupe.
- [Console variables](https://warcraft.wiki.gg/wiki/Config.wtf_defaults): character and account scope of CVars, and the config-cache files.
- [Leatrix Plus](https://www.curseforge.com/wow/addons/leatrix-plus): "Restore chat messages" keeps recent chat across a reload.
