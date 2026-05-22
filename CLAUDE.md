# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PvP Enemy is a World of Warcraft Classic addon that tracks enemy faction players who kill you and alerts you when you encounter them again. The purpose is revenge tracking on PvP servers.

## Architecture

The addon uses a shared namespace table (`ns`) passed via the `...` vararg to all files. All inter-file communication goes through this namespace.

**File loading order** (defined in `PvPEnemy.toc`):

1. **Core.lua** — Addon initialization, SavedVariables setup, database helpers (`ns.AddEnemy`, `ns.RemoveEnemy`, `ns.IsEnemy`, `ns.GetEnemy`), slash command handler (`/pvpenemy`, `/pve`)
2. **Tracker.lua** — Listens to `COMBAT_LOG_EVENT_UNFILTERED` to track the last hostile player who damaged you. On `PLAYER_DEAD`, identifies the killer and triggers the add-to-list popup (or auto-increments if already tracked)
3. **Scanner.lua** — Monitors `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT` to detect known enemies nearby. Includes a 30-second per-player alert cooldown
4. **UI.lua** — Two main UI elements: a top-of-screen warning banner (`PvPEnemyWarningFrame`) with red flash + sound, and a death popup (`PvPEnemyPopupFrame`) asking whether to add the killer to the list

## Data Storage

`SavedVariables: PvPEnemyDB` persists between sessions. Structure:
```lua
PvPEnemyDB = {
    enemies = { ["Name-Realm"] = { kills, lastKill, level, class, race } },
    settings = { soundEnabled, flashEnabled, alertDuration },
}
```

## Key Design Decisions

- **TOC Interface version `20505, 11507`** — oba typy realmů sdílí `_classic_era_` klient; `20505` = TBC Anniversary (patch 2.5.5), `11507` = Classic Era. Wrath: 30403, Cata: 40402, MoP: 50500, Retail: 110100
- Enemy names are stored as `"Name-Realm"` to handle cross-realm encounters
- Scanner does fuzzy matching on just the name part (before `-`) for same-server players
- All subsystems register via `ns.Init*()` functions called from Core.lua's `ADDON_LOADED` handler

## Slash Commands

`/pvpenemy` or `/pve` — `list`, `remove <name>`, `clear`, `sound`, `flash`

## Workflow Preferences

- **Web browsing**: For routine web fetches and searches (docs lookup, API references, simple research), delegate to a Haiku subagent via the `Agent` tool with `model: "haiku"`. This conserves tokens in the main context. Only do web work directly when it's a quick one-off or when results need deep synthesis with the current task.
