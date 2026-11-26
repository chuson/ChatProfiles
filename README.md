# ChatProfiles

A WoW Forever addon that saves your chat setup as a named profile and shares it between characters. Set up chat once, and every character using the profile gets the same tabs, channels and colors. Changes made on any of them are saved back to the profile when you log out.

ChatProfiles works on the standard chat window, using the same settings as the game's chat menus. Chat addons that restyle that window should keep working. Addons that replace it with their own window aren't supported.

## Installing

- **WowUp:** choose "Install from URL" and paste this repository's link. WowUp keeps it up to date.
- **By hand:** download the zip from the [latest release](../../releases/latest) and extract it into `World of Warcraft\_forever_\Interface\AddOns`.

Then restart the game or return to character select.

## Using it

Open the panel from Esc > Options > AddOns > ChatProfiles, or type `/chatprofiles` or `/chatp`.

- **New** saves your current chat settings as a profile and switches this character to it.
- **Choosing a profile** from the menu applies it to this character. If the character isn't using a profile and its settings don't match any of your profiles, you're asked first.
- **Save now** saves without waiting for logout.
- **Rename** and **Delete** do what they say. Characters using a deleted profile keep their chat settings.
- **Export** gives you text to paste to another account or a friend, and **Import** adds a profile from that text.

A profile is applied when you log in. Logging out or typing `/reload` always saves your chat settings to it, whether or not you clicked Save now. Switching to another profile is the only way to discard unsaved changes. The panel lists anything that differs from the profile.

If some settings can't be applied, ChatProfiles stops saving for that character until you reload or log in again, so a half-applied setup never overwrites a profile other characters share. The panel shows what didn't apply.

## What a profile saves

You choose which parts each profile saves. At least one is required.

- **Tabs:** which tabs you have, their order, the position of undocked tabs, and whether each tab is locked.
- **Message filters:** which messages and channels each tab shows.
- **Font and background:** text size, background color, and background opacity.
- **Chat colors:** the color of each kind of message, and whether names use class colors.

It doesn't save:

- **General's position.** Edit Mode controls it, and Edit Mode layouts can already differ per character.
- **Combat log filters.** The game already shares them across your account.
- **Channel membership.** ChatProfiles never joins or leaves channels.

## Reporting a bug

Open an issue with:

- What you did, what you expected, and what happened instead.
- The client build, from `/run print(GetBuildInfo())`.
- Any Lua error text. Turn error popups on with `/console scriptErrors 1` if you don't see any.
- The status lines from the `/chatprofiles` panel, if they're relevant.

## How this was made

I wrote ChatProfiles with Claude as a coding assistant. I'm a software engineer and SRE by trade, and I treated it the way I'd treat any code I'm responsible for. I set the design and requirements, reviewed the code function by function, and tested every change in game. Several bugs were found only through in-game testing and fixed before release. The addon has automated tests that check its logic against data recorded from a real client, and the commit history shows which changes were AI-assisted.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright (C) 2026 chuson

ChatProfiles is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.
