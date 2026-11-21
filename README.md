# DanTools

A set of small tools for World of Warcraft: Forever. Each tool can be turned on or off, and each
on-screen display can be dragged, locked and restyled (font, size, background, border).

## Tools

| Tool | What it does |
| --- | --- |
| Speed | Your movement speed as a percentage. |
| Time to Kill | How long the current fight has lasted, an estimate of when the target dies, and mana spent per kill. |
| XP Rate | XP per minute or per hour, and time to level. |
| Gold Rate | Gold per hour, with earned and spent totals. |
| Five-Second Rule | Countdown until mana regen resumes after spending mana, as a bar or text. |
| Drink Timer | Time until you are full while eating or drinking, as bars or text. |
| Enemy Alert | Lists nearby enemy players. Click a name to target them. |
| Grudge List | Remembers enemy players who killed you, and marks their nameplate and tooltip. |
| Bag Value | Vendor price on bag items, with the cheapest item outlined. |
| Item Level | Item level on gear in your bags and on the character screen. |

## Install

**CurseForge app:** search for DanTools under World of Warcraft, Forever.

**By hand:** download the zip from the
[latest release](https://github.com/radicaldancool/DanTools/releases/latest) and unzip it into
`World of Warcraft\_forever_\Interface\AddOns`. Use the release zip, not the green "Code" button:
the folder has to be named `DanTools`.

## Commands

- `/dantools` opens the settings window. The minimap button does the same.
- `/grudge` opens the Grudge list.

## Releasing

Set the new number on the `## Version:` line of `DanTools.toc`, commit, then push a matching tag:

```
git tag -a v2.0.1 -m "v2.0.1"
git push origin main v2.0.1
```

The tag starts the Release workflow, which builds the zip and publishes it.
