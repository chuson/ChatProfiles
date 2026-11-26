# ChatProfiles

A WoW Forever addon that saves your chat setup as a named profile and shares it between characters. Set up chat once, and every character using the profile gets the same tabs, channels and colors. Changes made on any of them are saved back to the profile when you log out.

ChatProfiles works on the standard chat window, using the same settings as the game's chat menus. Chat addons that restyle that window should keep working. Addons that replace it with their own window aren't supported.

## Installing

Copy the `ChatProfiles` folder into `World of Warcraft\_forever_\Interface\AddOns`, then restart the game or return to character select.

## Using it

Open the panel from Esc > Options > AddOns > ChatProfiles, or type `/chatprofiles` or `/chatp`.

- **New** saves your current chat settings as a profile and switches this character to it.
- **Choosing a profile** from the menu applies it to this character. Your current settings are saved to the old profile first.
- **Save now** saves without waiting for logout.
- **Rename** and **Delete** do what they say. Characters using a deleted profile keep their chat settings.
- **Export** gives you text to paste to another account or a friend, and **Import** adds a profile from that text.

A profile is applied when you log in, and your chat settings are saved to it when you log out or `/reload`. The panel lists anything that differs from the profile.

If some settings can't be applied, ChatProfiles stops saving for that character until you reload or log in again, so a half-applied setup never overwrites a profile other characters share. The panel shows what didn't apply.

## What a profile saves

You choose which parts each profile saves. At least one is required.

- **Tabs:** which tabs you have, the position of undocked tabs, and whether each tab is locked.
- **Message filters:** which messages and channels each tab shows.
- **Font and background:** text size, background color, and background opacity.
- **Chat colors:** the color of each kind of message, and whether names use class colors.

It doesn't save:

- **General's position.** Edit Mode controls it, and Edit Mode layouts can already differ per character.
- **Combat log filters.** The game already shares them across your account.
- **Which messages the Combat Log tab shows.**
- **Channel membership.** ChatProfiles never joins or leaves channels.

## Reporting a bug

Open an issue with:

- What you did, what you expected, and what happened instead.
- The client build, from `/run print(GetBuildInfo())`.
- Any Lua error text. Turn error popups on with `/console scriptErrors 1` if you don't see any.
- The status lines from the `/chatprofiles` panel, if they're relevant.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
