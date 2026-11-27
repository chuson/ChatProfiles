# ChatProfiles: Design Doc

Status: matches the addon as built, checked against Blizzard's UI source, in-game checks and recordings of a real client. Target client: WoW Forever 1.60.1 (build 71037, interface 16001), whose UI code most closely matches retail 12.1.5. Scope: profiles of chat settings that characters use, with changes saved automatically and shared across every character using the same profile, plus import and export.

## 1. Problem

Chat window setup (tabs, message groups, per-tab channels, appearance) is configured per character, so every new alt starts from defaults. The client has no "copy from character" feature. Hand-copying `chat-cache.txt` between character folders is the folk workaround, but it needs the game closed and depends on server-sync behavior we cannot verify. ChatProfiles does the transfer in game through the chat APIs.

## 2. Goals and non-goals

**Goals**

- Named profiles captured from, and applied to, the live chat setup.
- A character uses one profile at a time. Chat changes made on it are saved into the profile automatically at logout, or at once with **Save now**, and every other character using that profile receives them at its next login.
- Move a setup between characters on one account by selecting the profile on each, and between players with an export string.
- Small codebase, no libraries, no polling, no hooks on Blizzard functions. Readability comes before line count.

**Non-goals**

- Channel *membership* (joining or leaving). Profiles only control which channels each tab shows.
- Combat log filters. `Blizzard_CombatLog` saves them account-wide, so they already follow every character (section 10, question 8).
- General's position and size, which Edit Mode controls (section 10, question 15).
- Chat behavior settings (chat style, whisper mode, timestamps, chat bubbles, mouse-wheel scroll). They are stored per account (section 3), so they already follow every character.
- A default profile for new characters. Deferred.
- Undo. Players can export a profile to keep a copy.

## 3. API surface

Observed on the live client, and checked against Blizzard's 12.1.5 UI source (section 12):

| Purpose | API | Notes |
| --- | --- | --- |
| Read window | `GetChatWindowInfo(i)` | name, size, r, g, b, a, shown, locked, docked, uninteractable. `shown` and `locked` are booleans. `docked` is the dock position, or nil for an undocked, closed or unused window. `shown` is current visibility, so docked tabs that aren't selected report false. |
| Read groups | `GetChatWindowMessages(i)` | varargs of group names |
| Read channels | `GetChatWindowChannels(i)` | name, zoneChannelID pairs. Returns the channels the window is *configured to show*, not membership. A fresh character's window 1 lists the full default set (section 10, question 11). |
| Read position | `GetChatWindowSavedPosition(i)`, `GetChatWindowSavedDimensions(i)` | A corner (`TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT` or `BOTTOMRIGHT`) and x and y offsets as fractions of the screen size, then width and height. A window keeps its saved position after it's docked again, and every window reports a default size (section 10, question 15). |
| Groups | `frame:AddMessageGroup(group)` / `frame:RemoveMessageGroup(group)` | The `ChatFrame_*` globals are deprecated aliases of these methods and exist only while the `loadDeprecationFallbacks` CVar is on. It is on here, but we don't rely on it. |
| Channels | `frame:AddChannel(name)` / `frame:RemoveChannel(name)`, `C_ChatInfo.GetChannelShortcutForChannelID(id)` | The shortcut call turns a zone channel ID into the channel's local name. |
| Tabs | `FCF_OpenNewWindow(name, noDefaultChannels)`, `FCF_Close(frame)` | `FCF_OpenNewWindow` returns `frame, index`, or nothing when every slot is in use. Unless `noDefaultChannels` is set, it adds SAY, YELL, GUILD, WHISPER, BN_WHISPER, PARTY, PARTY_LEADER and CHANNEL. It unlocks the new window, then docks it at the end and selects it, and docking locks it again. It doesn't check for an existing tab with the same name. `FCF_Close` undocks and hides the window and clears its groups and channels. |
| Docking | `FCF_DockFrame(frame, index)`, `FCF_UnDockFrame(frame)`, `FCF_SetTabPosition(frame, 0)`, `FCF_CheckShowChatFrame(frame or tab)` | `FCF_DockFrame` inserts at `index` and locks the tab, and returns early for a tab that's already docked. `FCF_UnDockFrame` leaves the tab in the dock's tab bar and doesn't show a hidden window, so it's followed by `FCF_SetTabPosition` and `FCF_CheckShowChatFrame` for the window and its tab, as Blizzard's unlock path (`FCF_ToggleLock`) does. An undocked window also stays where the dock drew it, over General, until `FCF_RestorePositionAndDimensions` moves it to its saved position. General can't be undocked. `FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)` and `FCFDock_SelectWindow(GENERAL_CHAT_DOCK, frame)` read and restore the selected tab. |
| Position | `SetChatWindowSavedPosition(i, point, x, y)`, `SetChatWindowSavedDimensions(i, width, height)`, `FCF_RestorePositionAndDimensions(frame)` | The restore applies the saved values to the window. It skips General, whose position belongs to Edit Mode. |
| Appearance | `FCF_SetChatWindowFontSize(nil, frame, size)`, `FCF_SetWindowColor`, `FCF_SetWindowAlpha`, `FCF_SetLocked(frame, isLocked)` | Signatures confirmed in source. Color and alpha take a trailing `doNotSave`, which we leave nil. |
| Chat colors | `ChatTypeInfo[type]` (`r`, `g`, `b`, `colorNameByClass`), `ChangeChatColor(type, r, g, b)`, `SetChatColorNameByClass(type, enabled)` | `ChatTypeInfo` is an empty proxy once chat loads (section 10, question 13). Both setter signatures are confirmed in game, and recoloring also updates lines already in the window (section 10, question 12). `CHANNEL1` to `CHANNEL20` colors follow the character's local channel numbers. |
| Limits | `Constants.ChatFrameConstants.MaxChatWindows`, `C_ChatInfo.GetNumReservedChatWindows()` | 10 windows, of which 3 are reserved. `NUM_CHAT_WINDOWS` is a deprecated alias. |

Window numbers are not tab positions. Windows 1 to 3 are reserved (`C_ChatInfo.GetNumReservedChatWindows()` returns 3): General, Combat Log, and a Voice transcription window. The Voice window isn't shown or docked, but it still occupies a number, and `FCF_OpenNewWindow` never reuses it. Custom tabs start at 4. A window counts as *open* when it's shown or docked. Docked tabs report `shown = false` while another tab is selected, so `shown` alone isn't enough, and a window keeps its name after its tab is closed, so a name isn't enough either.

CVars: `synchronizeChatFrames = 1`, `synchronizeConfig = 1` (Blizzard's own sync stays on). `synchronizeSettings` and `synchronizeMacros` read `nil`. `loadDeprecationFallbacks = 1`.

The chat behavior CVars `chatStyle`, `whisperMode`, `showTimestamps`, `chatBubbles` and `chatMouseScroll` are stored per account and not per character (`C_CVar.GetCVarInfo` on the live client), so they already follow every character. `chatClassColorOverride` is stored in the local config, neither per account nor per character on the server.

Each character's `WTF\Account\<account>\<realm>\<character>\chat-cache.txt` is the client's copy of that character's chat setup. It has a `COLORS` section with every chat type's color, and a `WINDOW` block per window with its message groups, custom channels by name, and zone channels as a `ZONECHANNELS` bitmask in which bit n is zone channel ID n+1. ChatProfiles never reads the file; it shows what the client stores per character.

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

A window entry holds:

- `key`: `"window:1"`, `"window:2"`, or `"name:<tab name>"` for custom tabs.
- `name`.
- With Tabs on: `locked`, `docked` (`true` or `false`), and for undocked tabs only, `point`, `xOffset`, `yOffset`, `width` and `height` from the saved position.
- With Font and background on: `fontSize`, `r`, `g`, `b`, `a`.
- With Message filters on: a sorted array `messageGroups`, and an array `channels` of `{ name, zoneChannelID }` sorted by name.

The list holds tabs, but it's called `windows` because that's the client's word. Docked tabs come first, in dock order, then undocked tabs by window number, so a tab's place in the list gives its place in the dock. A profile's `colors` maps each `ChatTypeInfo` key to `r`, `g`, `b` and `classColoredNames`.

Profiles saved by any released version must keep working, unless a release announces a breaking change in its notes. A setting a profile lacks is left alone, so a new optional field needs no migration.

- Profiles are keyed by name. The `profileByCharacter` table is account-wide, so rename updates every reference in one loop, and delete detaches the characters that used the profile.
- Character keys are `UnitName("player") .. "-" .. GetNormalizedRealmName()`. On Forever the realm name is empty, so keys look like `"Name-"`. Forever character names are unique across the game, so the empty realm can't cause a collision. Other game versions get the usual `"Name-Realm"`, and each version keeps its own saved variables, so keys from different versions never meet.
- A profile holds only its current setup: no version number and no history. Whether a character is in sync is answered by comparing its live chat with the profile.
- A renamed or transferred character looks unassigned under its new key. This is harmless: the player selects a profile again.
- Saved variables are initialized in `ADDON_LOADED` for ChatProfiles (they aren't available at file scope), and the event is then unregistered. `schema` is stored so a later format change can be detected, but no migration code is written until a second schema exists. The table is assigned to the global `ChatProfilesDB`, not only to a local, or the client has nothing to write. Chat state is never read at this point: on a fresh login it still predates the client's settings download (section 10, question 1).
- Windows 1 and 2 are matched by number. Custom tabs are matched by name. If two open tabs share a name, only the first is used and the panel lists the name.
- With Tabs on, apply makes the set of open custom tabs equal to the profile: it creates missing tabs and closes the ones the profile doesn't contain. Windows 1 and 2 are never closed. It also docks or undocks tabs to match, and moves and resizes undocked tabs. With Tabs off, apply only updates tabs that already exist.
- A font size of `0` means no size was ever saved, and the window keeps its default font. Apply leaves it alone (section 10, question 6).
- A channel with a `zoneChannelID` above 0 is matched by ID, and on apply its name comes from `C_ChatInfo.GetChannelShortcutForChannelID`, so it carries across locales. A channel with `zoneChannelID` 0 is matched by name, ignoring case (section 10, question 16).

### Setting categories

Each profile stores which categories it manages (`categories`). A category that's turned off is neither applied nor saved, so the character, or another addon, keeps control of it. Checkbox changes are unsaved changes like any other: the panel lists them, the next save (Save now or logout) stores them, and switching profiles discards them. Turning a category off drops its saved data only when that save happens, so an abandoned change leaves the profile as it was. A profile always keeps at least one category on. With every box unchecked, the panel shows a warning in red, disables Save now, and saving is skipped, so the profile keeps its last saved selection. Imports with none on are rejected. The panel shows each one with a short description.

| Category | Panel description | Default | Notes |
| --- | --- | --- | --- |
| Tabs | Which tabs you have, their order, the position of undocked tabs, and whether each tab is locked | on | Off: apply never creates, closes, docks, reorders or moves tabs. |
| Message filters (`messagesAndChannels`) | Which messages and channels each tab shows | on | Includes the Combat Log tab's groups, such as XP and honor gains, which are stored per character (section 10, question 14). |
| Font and background | Text size, background color, and background opacity | on | |
| Chat colors | Colors for all message types | on | Includes class-colored names. Stored per character (section 10, question 10). Channel colors follow local channel numbers (section 9). |

Outside every category: chat behavior settings and combat log filters, which are account-wide (section 3, question 8), and General's position (Edit Mode).

## 5. Architecture

Five small files, one shared namespace (`local _, ns = ...`), dependencies in one direction. `Profiles.lua` registers three events: `ADDON_LOADED`, to initialize saved variables; `PLAYER_LOGIN`, to apply the character's profile; and `PLAYER_LOGOUT`, to save the selected profile. `ADDON_LOADED` and `PLAYER_LOGIN` are unregistered after they fire. The options panel is registered when its file loads, and its widgets are built the first time it opens.

| File | Responsibility | Depends on |
| --- | --- | --- |
| `ChatSettings.lua` | Read live state, compare it with a profile, apply. Returns results, never prints, never touches saved data. | WoW chat APIs |
| `ExportString.lua` | Profile to export string and back, including validation of imported data. Uses only `C_EncodingUtil`, `Constants` and `ChatTypeInfo`, so the tests can stand in for them. | none |
| `Profiles.lua` | Owns `ChatProfilesDB`. New, rename, delete, import; select a profile for the current character; apply it at login; save live chat into it, including at logout. | `ChatSettings` |
| `PanelText.lua` | The panel's status line, list of changes and export hint, worked out from `Profiles`. Kept apart from the frames so the tests can check it. | `Profiles` |
| `OptionsPanel.lua` | The options panel, its popups, and the slash commands. Calls `Profiles` and `ExportString`, and shows the results. | `Profiles`, `ExportString`, `PanelText` |

### Engine API

```lua
ChatSettings.Read(categories)       -- -> live settings: windows, windowNumbers, duplicateTabNames, colors
ChatSettings.Diff(live, profile [, categories])  -- -> { {text=, apply=, pass=}, ... }   (empty = in sync)
ChatSettings.Apply(profile)         -- -> remaining differences (empty = success), first error raised
```

Design points:

- One comparison drives everything. The panel lists each difference's text, and Apply runs the same entries, so the two can't disagree. The post-apply check calls `Diff` again and tests for an empty list.
- `Read` returns only open windows, so the Voice window and closed tabs drop out without special cases. Window numbers go in `windowNumbers`, kept out of `windows` because they differ between characters.
- `Read` and `Diff` skip categories the profile doesn't include, so one switch stops both applying and saving that category.
- Each change runs under its own `pcall`, so one bad call doesn't stop the rest. Apply ends by reading again and returns what still differs, so a thrown error and a silent no-op are reported the same way.
- Saved positions are compared within 0.001 of the screen size, sizes within half a pixel, and colors within 0.01, since the client rounds what it stores.
- `Apply` makes changes in three passes, comparing again before each:
  1. Close extra tabs, then open missing ones with `FCF_OpenNewWindow(name, true)`. Closing comes first so a new tab has a free slot.
  2. Undock tabs, including new ones the profile has undocked. `FCF_DockFrame` inserts at the index it's given, so a tab still in the dock when another is docked would push it one place right. Undocking also moves the window to its saved position: a tab keeps that position while docked, so when it matches the profile, pass 3 has nothing to change and wouldn't move the window.
  3. Everything else: the order of docked tabs, then each tab's docking, position and size, lock, appearance, groups and channels, then colors. Docking comes before the lock, since docking locks a tab.
- A tab is docked at its place among the profile's docked tabs. General and the Combat Log are static tabs (`isStaticDocked`): the dock always draws them first, and other tabs can't be dragged between them, so they're left out of the order and the Combat Log is always docked second.

## 6. Selecting, saving and syncing

A character uses at most one profile. Selecting a profile applies it, and while it stays selected the character's chat changes are saved into it automatically. Characters that use the same profile converge: a change saved by one is applied on the others at their next login.

| Trigger | Condition | Action |
| --- | --- | --- |
| Login (`PLAYER_LOGIN`) | uses a profile | apply the profile, after combat ends if it started in combat; on failure, stop saving this session |
| Select a profile | not in combat | discard unsaved changes, then apply the new one |
| New | always | live chat becomes a new profile, and this character uses it |
| Save now (panel button) | uses a profile, saves not skipped | save live chat into the profile immediately |
| Logout (`PLAYER_LOGOUT`) | uses a profile, saves not skipped | save live chat into the profile |

- **Login** (`PLAYER_LOGIN`, which also fires on `/reload`): apply the profile. Apply only changes what differs, so a character already in sync is left alone. If anything still differs afterward, the session is marked failed and chat prints a short warning. The apply runs one frame after the event (`C_Timer.After(0)`), so other addons' login handlers, such as chat history restore, finish first. The client's downloaded chat settings arrive before `PLAYER_LOGIN` and nothing changes afterward (section 10, question 1), so there is no retry and no fixed delay.
- **Combat.** The game blocks some chat changes in combat, and a blocked change does nothing without raising an error, so an apply in combat fails and stops saving. Selecting a profile in combat is refused with a message. If a `/reload` happens in combat, the login apply waits for `PLAYER_REGEN_ENABLED`, and saves are skipped until it runs, since the live settings aren't the profile's yet.
- **Select** (panel menu): apply the new profile and list anything that didn't take. If a change raised an error, chat shows the first one, as at login. Unsaved changes, including checkbox changes, are discarded rather than saved into the old profile: switching away while Save now is available means the player chose not to keep them, and the old profile stays as last saved. **None** detaches the character without saving.
- **Save** is `Profiles.SaveSelected()`: it replaces the profile's windows and colors with `ChatSettings.Read()`. It saves even when nothing seems to differ, because a category that was just turned on has no saved data yet, so the comparison can't see its changes. Categories that are turned off are dropped, and with every category off it saves nothing rather than emptying the profile. It runs at `PLAYER_LOGOUT` and on **Save now**. `PLAYER_LOGOUT` fires on both logout and `/reload`, the chat APIs still return the live setup when it fires (section 10, question 2), and it is the last event before saved variables are written.
- **New** saves the live setup as a new profile and switches this character to it, starting from the checkboxes as they are (or all four, if none is checked) so a category turned off on purpose stays off. The previous profile is left as it was.
- **No version numbers.** Login and logout use the same comparison with opposite winners: the profile wins at login, and the character wins at logout, so a character that changed its chat has always saved before the next login. The one case this can't distinguish is a session that ended without its logout save (a crash, or a skipped save). The next login then restores the profile, and that session's changes are lost. This matches the accepted crash risk in section 9.
- **Skipped saves.** Save now and the logout save are both skipped:
  - after an apply (at login or on select) leaves differences or raises an error, until an apply succeeds, New is used, or the player reloads. A half-applied state must not overwrite the profile, because other characters share it.
  - while the login apply waits for combat to end, since the live settings are still the character's own.
  - while no category is checked, so the profile keeps its last saved selection.

  Save now is disabled at those times, and the panel says why.
- ChatProfiles neither relies on nor changes the client's own chat upload (`synchronizeChatFrames = 1`).

### Compatibility with other chat addons

- Apply only changes what differs, so a routine login or `/reload` changes nothing.
- ChatProfiles reads and writes chat configuration only. It never reads, clears or re-adds chat lines, so 12.x secret messages never pass through it, and it hooks no Blizzard functions.
- Existing windows are updated in place and keep their window number. History addons that appear to key saved chat by window index, such as Leatrix Plus "Restore chat messages", keep each tab's history with the right tab.
- The login apply waits one frame after `PLAYER_LOGIN`, so other addons' login handlers, including chat history restore, run first.
- Closing a tab is the one destructive step: it discards that tab's scrollback, including any restored history. It only happens with Tabs on, when the profile lacks the tab.
- If another addon also sets up chat at login, the two would conflict on every login, and the logout save would capture the other addon's result. The panel shows the differences, and turning off the category that addon manages resolves it.

## 7. Import and export

- Format: `ChatProfiles1:<payload>`, where the prefix versions the format.
- Payload: `C_EncodingUtil.SerializeCBOR`, then `EncodeBase64`. There is no compression. Profiles are a few KB, and `DecompressString` has no caller-set size limit (a hard cap of about 100 MB), so a small crafted string could force a large allocation.
- Export writes the *saved* profile. When the character has unsaved changes, the panel says to Save now to include them.
- **Strings are data, never code.** Import checks the length first (64 KB), removes spaces and line breaks (forums and chat apps wrap long lines, and Base64 never contains either), checks the prefix, and decodes under `pcall`. It then validates against a whitelist before anything is stored, and stops at the first problem:
  - known fields only, with type checks, at every level
  - categories are booleans, and at least one is on
  - at most 10 tabs, no two with the same key, and keys of `window:1`, `window:2` or `name:...`; a custom tab's key is rebuilt from its name
  - font size 0 or a whole number from 6 to 40; colors and opacity from 0 to 1; the lock and docked state are booleans
  - General can't be undocked; a position or size needs `docked = false`; the corner is one of the four; offsets are from -1 to 1; width and height are above 0 and at most 4096
  - message groups are uppercase letters, digits and underscores, at most 100 per tab; at most 100 channels per tab, each with a whole-number ID of 0 or more
  - at most 200 chat colors, each a `ChatTypeInfo` key this client knows
  - tab and channel names at most 200 bytes, valid UTF-8, with no control characters and no single `|`, since `|c`, `|H` and `|T` start the client's escape sequences; `||`, the client's literal `|`, is allowed
- A string that fails a check is rejected with the reason shown, and untrusted text in the reason is cut to 30 bytes with codes and line breaks removed. Nothing is clamped or fixed, so an import either matches what was exported or isn't added.
- Import only adds a profile to the list, under a name the player gives it. Applying is a separate act.
- Profile names are trimmed of spaces at both ends (including U+00A0 and U+3000), must be 1 to 50 characters, can't contain `|` or line breaks, and must be unique.

## 8. UI

A canvas category under **Esc > Options > AddOns > ChatProfiles**, also opened by `/chatprofiles` or `/chatp`. It is registered with `Settings.RegisterCanvasLayoutCategory(frame, name)` and opened with `Settings.OpenToCategory(category:GetID())`. The older pattern of opening by name is reported broken on current clients.

```
ChatProfiles
Share one chat setup across your characters. Changes are saved when you log out.

Profile
[ Main            v ]  [New]  [Rename]  [Delete]
[Save now]  2 unsaved changes. They'll be saved when you log out.
General: doesn't show the Trade channel
whispers: undocked instead of docked

Saved in this profile
[x] Tabs
    Which tabs you have, their order, the position of undocked tabs, and whether each tab is locked
[x] Message filters
    Which messages and channels each tab shows
[x] Font and background
    Text size, background color, and background opacity
[x] Chat colors
    Colors for all message types

Sharing
[Export]  [Import]
[ text box, shown after Export or Import ]
[Add profile]  Paste a ChatProfiles export in the box, then click Add profile.
```

Behavior:

- The status line reads one of:
  - "This character isn't using a profile."
  - "Your chat settings match the profile."
  - "N unsaved changes. They'll be saved when you log out."
  - "Exit combat to apply changes.", while the login apply waits for combat to end. Nothing is listed, since the live settings aren't the profile's yet.
  - After a failed apply, that changes won't be saved until a reload or login.
- Up to 8 differences are listed below the status line, followed by any duplicate tab names. The status is worked out when the panel opens, after each of its actions, and when the mouse comes back over the panel. Changing chat settings fires no events (checked in game by listening for every chat-related event), so returning to the panel is the cue that something may have changed.
- Selecting a profile applies it and discards unsaved changes, so switching away is how to abandon them. In combat, red text at the top of the screen says profiles can't be switched, and nothing changes.
- On a character that isn't using a profile, selecting one asks for confirmation in a popup if its chat settings would be lost: they differ from the chosen profile, and from every profile that saves at least the same categories. The popup suggests clicking New first to keep them.
- Checkbox changes count as unsaved changes and are listed first, for example "Chat colors turned off". Only categories that are saved and still checked list their differences, so a category being turned off shows only that line. While no box is checked, a red line under the checkboxes says changes aren't saved, and Save now is disabled.
- **New** and **Rename** ask for a name in a popup. A rejected name shows the reason at the top of the screen and keeps the popup open. Renaming to the same name just closes it.
- **Delete** confirms in a popup. Characters using the profile keep their chat settings.
- **Export** shows the export string in the box, selected for Ctrl+C, since addons can't write to the clipboard. The string is the saved profile. While there are unsaved changes, a red note says to Save now to include them, and an open export updates itself after a save or a profile switch.
- **Import** shows an empty box and **Add profile**, which checks the string and then asks for a name in the same popup. A rejected string's reason appears in red beside Add profile. Once a profile is added, a line beside Import says so until the panel is opened again, since nothing else on the panel changes.
- The panel has no other confirmation messages: New, Rename and Delete show in the menu, and Save now in the status line.
- The page scrolls when its contents don't fit, which depends on screen size and UI scale.
- Chat settings change only by selecting a profile or through the game's own chat UI. Import adds a profile to the list and nothing else.
- **Save now** runs the same save as logout, immediately, so the status line and Export reflect the change at once. The client still writes it to disk at the next logout or `/reload`.
- The saved categories belong to the profile, so every character using it manages the same categories, and export strings carry the saved selection.

## 9. Risks and accepted trade-offs

- No undo. Selecting a profile on a character that uses none overwrites its setup with nothing saved first. Mitigation: if the setup matches no profile, the panel asks for confirmation and suggests New first.
- A change on one character is saved into the shared profile and applied on every character that uses it at its next login. Two characters using the same profile: last logout wins. Accepted.
- Switching profiles discards unsaved changes. Accepted: Save now is beside the menu, and discarding keeps the old profile exactly as last saved.
- A failed apply skips saving (section 6), so partial failures can't spread through a shared profile.
- The login apply relies on the client's chat settings being final by `PLAYER_LOGIN`, which was measured on one character (section 10, question 1). The post-apply check and the apply guard catch a late overwrite if one happens.
- Chat APIs may change between patches. The engine isolates them in one file, the post-apply comparison surfaces silent no-ops, and the `Read` tests replay a recording of a real client, which can be redone after a patch.
- A session that ends without its logout save (a crash, or a skipped save after a failed apply) loses that session's chat changes. The profile wins at the next login.
- Imported strings are untrusted input. Validation (section 7) is the control.
- With every window slot in use, `FCF_OpenNewWindow` creates nothing, and the missing tab stays in the remaining differences.
- Closing a tab discards its scrollback, including history restored by another addon. It only happens with Tabs on, when the profile lacks the tab.
- Channel colors are stored per channel number (`CHANNEL1` to `CHANNEL20`), and two characters may number the same channel differently, for example when one has joined an extra channel. The color then lands on whichever channel holds that number. Accepted.
- A custom channel shown in a tab may not stick on a character that hasn't joined it. If it doesn't, the difference stays, the apply counts as failed, and that character stops saving. Untested.
- Another addon that rebuilds chat at login would conflict with ChatProfiles on every login. Mitigation: turn off the category that addon manages.

## 10. Questions about the client

These were open while the addon was designed, and are all answered now. The answers come from Blizzard's 12.1.5 UI source (section 12), in-game checks, a temporary probe addon, recordings of a real client (`tests/fixtures/ChatRecording.lua`), and the client's own saved files. They keep their numbers so references hold.

1. **Login apply.** On a fresh login the chat setup changes on `UPDATE_CHAT_WINDOWS` twice, the second time just after `VARIABLES_LOADED` (the server download, about 5 seconds in). From `PLAYER_LOGIN` on it stays unchanged through 15 seconds after `PLAYER_ENTERING_WORLD`. On `/reload` it is already final when `ADDON_LOADED` fires. Event order on both: `VARIABLES_LOADED`, `PLAYER_LOGIN`, `SETTINGS_LOADED`, `PLAYER_ENTERING_WORLD`. Apply at `PLAYER_LOGIN` with no retry; never read chat at `ADDON_LOADED`.
2. **Logout save.** `PLAYER_LOGOUT` fires on both logout and `/reload`, and the chat APIs return the same setup as during play. No fallback save is needed.
3. **Window creation.** `FCF_OpenNewWindow` takes the first slot after the reserved ones that is neither shown nor docked, so the Voice window is never reused. It adds eight default groups unless `noDefaultChannels` is set, unlocks the window and then docks it, which locks it again (`FCF_DockFrame` ends with `FCF_SetLocked(frame, true)`), and returns nothing when all slots are in use.
4. **Closing windows.** `FCF_Close(frame)` undocks and hides the window and clears its groups and channels. Hiding clears the window's shown flag through its `OnHide` script, which frees the slot for `FCF_OpenNewWindow`.
5. **Locked flag.** `FCF_SetLocked` passes its value straight to `SetChatWindowLocked`, and `GetChatWindowInfo` returns `true` or `false` (recorded with a locked and an unlocked tab).
6. **Font size `0`.** No size was ever saved; the window keeps its default font, and Blizzard's own code skips setting the font for 0. Apply leaves it alone.
7. **Tab order.** `FCF_DockFrame(frame, index)` inserts at `index` but returns early for a tab that's already docked, so moving a docked tab means undocking it and docking it again. Apply docks a tab at its place in the profile's order, and when the docked tabs are out of order it undocks each one after the static tabs (General, and the Combat Log when docked) and docks it again at its place, then selects the previously selected tab again.
8. **Combat log filters.** `Blizzard_CombatLog.toc` lists `Blizzard_CombatLog_Filters` under `SavedVariables`, not `SavedVariablesPerCharacter`, so filters are account-wide. Confirmed on this client: `Blizzard_CombatLog.lua` is in the account-level `SavedVariables` folder.
9. **Group and channel names.** Group names are the keys of `ChatTypeGroup`. Channel names are localized, but `GetChatWindowChannels` also returns a zone channel ID, which `C_ChatInfo.GetChannelShortcutForChannelID` turns back into the local name, so channels are stored with both. The client does the same in `chat-cache.txt`. Confirmed in game: `C_ChatInfo.GetChannelShortcutForChannelID(47)` returns `OOC`.
10. **Chat colors per character.** Every character's own `chat-cache.txt` holds a `COLORS` section, so colors are stored per character and the Chat colors category is on by default.
11. **Default channels on window 1.** A character with an untouched setup shows zone channels 1, 2, 22, 32 to 36, 42, 46 and 47 on window 1. Decoding the `ZONECHANNELS` bitmask in each character's `chat-cache.txt` gives exactly the list `GetChatWindowChannels` returns in game.
12. **Chat color setters.** `ChangeChatColor(type, r, g, b)` and `SetChatColorNameByClass(type, enabled)` both take effect at once, tested with Say. Recoloring also updates lines already in the chat window.
13. **`ChatTypeInfo`.** Once chat loads, `ChatFrameUtil.ImportAllListsToHash` moves its entries into the metatable's `__index` and empties the table, so `ChatTypeInfo.SAY` works but `pairs(ChatTypeInfo)` finds nothing. `Read` loops over `__index`. The client has 92 chat types with colors; a few, such as `BN_ALERT`, have no `colorNameByClass`.
14. **Combat Log message groups.** The Combat Log tab reports message groups like any other tab (`OPENING`, `TRADESKILLS`, `PET_INFO`, `COMBAT_XP_GAIN`, `COMBAT_HONOR_GAIN` and `COMBAT_MISC_INFO` by default), and the player can change them in its settings. They're stored per character: adding `SKILL` and `LOOT` on one character left another's unchanged. They're saved under Message filters.
15. **Window position.** `FCF_SavePositionAndDimensions` stores a corner and offsets as fractions of the screen size, so saved positions work at any resolution. Docked tabs follow General and have no position of their own, but a tab keeps its saved position after it's docked again, so only undocked tabs store one. Every window reports a default size (430 × 120). General's position belongs to Edit Mode, and `FCF_RestorePositionAndDimensions` skips it.
16. **Custom channel names.** Channel membership ignores case, and the client reports a channel in the case it was joined with, so custom channels are matched ignoring case. Channels with Cyrillic names can't be joined.

## 11. Testing

The automated tests (`lua tests/run.lua`) check the addon's logic against stand-ins for the client, and CONTRIBUTING describes them. They can't show that the client behaves like the stand-ins, so changes are also checked in game.

**Live tests**

- Change a tab on a character that uses a profile, log out, log in, and confirm the profile holds it. Repeat with `/reload`.
- Log into a second character using the same profile and confirm it matches.
- Make a change, switch to another profile and back, and confirm the change was discarded.
- Undock a tab, save, switch to a profile with it docked and back, and confirm it returns to its position with its tab on the window.
- Switch to a profile that undocks one tab and docks another later in the order, and confirm no differences remain.
- Apply on a fresh character and confirm no differences remain.
- Rename and delete a tab on one character, and confirm both carry to a second.
- Apply with every window slot in use.
- Confirm Save now updates the status line and Export at once.

**Compatibility**

- With Leatrix Plus "Restore chat messages" on, `/reload` with nothing to apply and confirm history survives in every tab. Then apply a profile that changes groups and one that adds a tab, and confirm the existing tabs keep their history.

## 12. References

- [Blizzard UI source, 12.1.5.70961](https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns): `Blizzard_ChatFrameBase` (chat frame methods, `Mainline/FloatingChatFrame.lua` for docking, saved positions and `FCF_ToggleLock`, `ChatTypeInfoConstants.lua`), `Blizzard_DeprecatedChatInfo` (the `ChatFrame_*` aliases), `Blizzard_CombatLog` (filter storage), `Blizzard_StaticPopup`, `Blizzard_Settings_Shared`, and `Blizzard_APIDocumentationGenerated` (`C_EncodingUtil`, `C_ChatInfo`, chat constants).
- [GetChatWindowInfo](https://warcraft.wiki.gg/wiki/API:GetChatWindowInfo): return values.
- [Settings API](https://warcraft.wiki.gg/wiki/Settings_API) and [Settings.OpenToCategory](https://warcraft.wiki.gg/wiki/API:Settings.OpenToCategory): canvas registration and ID-based opening.
- [SerializeCBOR](https://warcraft.wiki.gg/wiki/API:C_EncodingUtil.SerializeCBOR), [DeserializeCBOR](https://warcraft.wiki.gg/wiki/API:C_EncodingUtil.DeserializeCBOR) and [DecompressString](https://warcraft.wiki.gg/wiki/API:C_EncodingUtil.DecompressString): serialization limits and the decompression cap.
- [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions): when saved variables load and are written.
- [Blizzard forums: adding a chat tab through code](https://us.forums.blizzard.com/en/wow/t/trouble-confusion-on-adding-a-chat-tab-through-code/185148): `FCF_OpenNewWindow` doesn't check for an existing tab with the same name.
- [Console variables](https://warcraft.wiki.gg/wiki/Config.wtf_defaults): character and account scope of CVars, and the config-cache files.
- [Leatrix Plus](https://www.curseforge.com/wow/addons/leatrix-plus): "Restore chat messages" keeps recent chat across a reload.
