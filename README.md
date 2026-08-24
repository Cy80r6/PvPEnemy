# PvP Enemy

A World of Warcraft **TBC Anniversary / Classic Era** addon that tracks enemy players who kill you and warns you when you encounter them again.

> **Open beta — everyone is welcome to test!**
> Found a bug or have a suggestion? Open an [Issue](../../issues) or leave a comment. All feedback is appreciated.

## What it does

**Kill tracking**
- When you die to an enemy player, a popup asks if you want to add them to your kill list
- Stores their name, class, race, level, how many times they've killed you, and where it happened
- Tracks your wins too — the addon notices when you kill someone on your list and counts it as a revenge

**Alerts**
- When you encounter a tracked enemy (nameplate, target, mouseover), a warning banner appears at the top of your screen with their name, class, kill/win count, last seen zone, and any note you've set
- Click the banner to target them instantly — works in combat too
- Optional screen flash and sound alert
- 30-second cooldown per enemy to avoid spam

**Notes & history**
- Add personal notes to any enemy (`/pvpenemy note`) — shown in the warning banner and kill list
- Full kill list with deaths, wins, level comparison, last kill time and zone

**Guild sharing**
- Optionally broadcast enemy alerts to your online guild members (`/pvpenemy share`)
- Uses a random 1–3s delay with deduplication — if multiple people spot the same enemy at once, only one alert goes out
- When a guildie spots your enemy and you kill them, a popup asks if you want to whisper them that you got revenge

**All data persists between sessions**

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
| `/pvpenemy share` | Toggle sharing enemy alerts with guild (default: off) |
| `/pvpenemy bg` | Toggle tracking in battlegrounds/arenas |


## Compatibility

- TBC Anniversary (patch 2.5.5, interface 20505)
- Classic Era (interface 11507)

## Changelog

### 1.3.0

- Click the warning banner to target the enemy immediately, no need to find their nameplate — works in combat too, since it's done via a secure macro (`/targetexact`) rather than a plain click handler that WoW would block mid-fight

### 1.2.0

Three things were quietly broken before this release. If you tested an earlier build, they are worth knowing about:

- **Guild sharing never worked.** It used a chat API that no longer exists on the Classic client, which also meant the `PvP Enemy loaded.` message never appeared at login. Both are fixed — if you see that message on login, sharing is live
- **Wins were never counted.** The addon was watching a combat log event that does not say who landed the killing blow, so the counter stayed at zero and the revenge popup never appeared
- **Alerts could fire for the wrong player.** A tracked `Celu` would set off the warning for any `Celu` you met, including a stranger from another realm. Names are now matched exactly, realm included

Your kill list is upgraded automatically the first time you log in on 1.2.0 — names get their realm filled in and any duplicate entries for the same player are merged. You will see a one-line summary in chat when it happens.

Also in this release: guild alerts carry a protocol version and are checked before use, a flood of alerts from one guildmate is throttled, and a subsystem that fails to start can no longer take the rest of the addon down with it.

## Feedback & Suggestions

This addon is in active development. If something doesn't work as expected, or you have an idea for a new feature — please open an [Issue](../../issues). Pull requests are also welcome.
