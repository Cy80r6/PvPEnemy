# PvP Enemy

A World of Warcraft **TBC Anniversary / Classic Era** addon that tracks enemy players who kill you and warns you when you encounter them again.

> **Open beta — everyone is welcome to test!**
> Found a bug or have a suggestion? Open an [Issue](../../issues) or leave a comment. All feedback is appreciated.

## What it does

- When you die to an enemy player, a popup asks if you want to add them to your kill list
- If you later encounter someone from your list (nameplate, target, mouseover), a warning banner appears with their name, class, and how many times they've killed you
- Data persists between sessions

## Installation

1. Download the latest zip from [Releases](../../releases)
2. Extract the `PvPEnemy` folder into:
   - **TBC Anniversary:** `World of Warcraft\_anniversary_\Interface\AddOns\`
   - **Classic Era:** `World of Warcraft\_classic_era_\Interface\AddOns\`
3. Reload the game or log in

## Commands

| Command | Description |
|---|---|
| `/pvpenemy list` | Show your kill list |
| `/pvpenemy add <Name[-Realm]>` | Manually add an enemy |
| `/pvpenemy remove <Name-Realm>` | Remove from list |
| `/pvpenemy clear` | Clear entire list |
| `/pvpenemy sound` | Toggle warning sound |
| `/pvpenemy flash` | Toggle screen flash |
| `/pvpenemy note <Name-Realm> <text>` | Set a personal note for an enemy (shown in list and alert) |
| `/pvpenemy alert <1-30>` | Set warning banner duration (seconds) |
| `/pvpenemy share` | Toggle sharing enemy alerts with party/raid (default: off) |
| `/pvpenemy bg` | Toggle tracking in battlegrounds/arenas |


## Compatibility

- TBC Anniversary (patch 2.5.5, interface 20505)
- Classic Era (interface 11507)

## Feedback & Suggestions

This addon is in active development. If something doesn't work as expected, or you have an idea for a new feature — please open an [Issue](../../issues). Pull requests are also welcome.
