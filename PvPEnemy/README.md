# PvP Enemy

WoW Classic addon — sleduje nepřátele, kteří tě zabili, a upozorní tě, až je potkáš znovu.

## Instalace

Zkopíruj složku `PvPEnemy` do:

- **TBC Anniversary:** `World of Warcraft\_anniversary_\Interface\AddOns\`
- **Classic Era:** `World of Warcraft\_classic_era_\Interface\AddOns\`

## Jak to funguje

- Když zemřeš, addon identifikuje posledního nepřítele, který tě poškodil, a nabídne ti ho přidat na kill list. Popup zobrazí jeho level, třídu a tvůj vlastní level v době smrti.
- Jakmile je někdo na listu, addon tě upozorní (flash + zvuk) kdykoliv ho uvidíš na nameplate, jako target nebo mouseover.
- Každý hráč má 30s cooldown na upozornění, aby tě to nespamovalo.

## Příkazy

| Příkaz | Popis |
|--------|-------|
| `/pvpenemy list` | Zobrazí kill list |
| `/pvpenemy add <Jméno[-Realm]>` | Ručně přidá nepřítele (realm se doplní automaticky) |
| `/pvpenemy remove <Jméno-Realm>` | Odebere ze seznamu |
| `/pvpenemy clear` | Smaže celý seznam |
| `/pvpenemy sound` | Zapne/vypne zvukové upozornění |
| `/pvpenemy flash` | Zapne/vypne flash efekt |
| `/pvpenemy bg` | Zapne/vypne tracking v BG a arénách (default: **vypnuto**) |

Zkratka: `/pve` funguje stejně jako `/pvpenemy`.

## Data

Ukládá se do `PvPEnemyDB` (SavedVariables) — přežívá restarty hry. Každý nepřítel má:

| Pole | Popis |
|------|-------|
| `kills` | Počet tvých smrtí způsobených tímto hráčem |
| `lastKill` | Timestamp posledního zabití |
| `level` | Level zabijáka v době posledního zabití (nebo `nil` pokud nešel zjistit) |
| `myLevel` | Tvůj level v době posledního zabití |
| `class` | Třída hráče (anglicky, velkými písmeny) |
| `race` | Rasa hráče |

Příkaz `/pvpenemy list` zobrazuje u každého nepřítele `[Lvl X vs your Y]`, takže vidíš level rozdíl při každém zaznamenaném zabití.

### Nastavení

| Klíč | Default | Popis |
|------|---------|-------|
| `soundEnabled` | `true` | Zvukový alert při detekci nepřítele |
| `flashEnabled` | `true` | Červený flash efekt |
| `alertDuration` | `5` | Délka zobrazení varovného banneru (sekundy) |
| `ignorePvPInstances` | `true` | Vypnout tracking v BG a arénách |
