# Strummer.lua

A guitar strumming pattern simulator for [REAPER](https://www.reaper.fm/), inspired by Ample Sound's Strummer module. Works with any guitar sample library that accepts standard MIDI — Ample Sound AGx series, Shreddage, Orange Tree Samples, and others.

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Reaper](https://img.shields.io/badge/REAPER-6.0%2B-blue)
![ReaImGui](https://img.shields.io/badge/ReaImGui-required-orange)
![Version](https://img.shields.io/badge/version-0.3-brightgreen)

---

## Features

- **Chord Mode / Guitar Mode** — Chord mode passes notes through as-is; Guitar mode automatically remaps any chord (or a single root note) to a physically playable six-string voicing, respecting string order, open tuning, and a maximum of 6 voices
- **Pattern grid** — Up to 32 steps per pattern; each step independently controls direction (↓/↑), velocity, time offset, and playing technique
- **Global step unit** — Set the base grid duration: 1/4, 1/8, 1/16, 1/32, triplets, or any custom value. All steps share the same base unit; silent steps act as rests
- **Per-step span** — Each step can optionally occupy multiple base units (×2, ×3, ×4…), enabling mixed note values within a single pattern without changing the global grid
- **Built-in rhythm library** — 25 patterns across Pop, Rock, Jazz, Blues, Funk, Folk, Reggae, Latin, and World styles; filterable by genre
- **User pattern library** — Save your own patterns; they persist across sessions automatically
- **Humanization** — Per-apply randomization of timing and velocity to simulate a real performance
- **Strum speed** — Controls the tick gap between each string, simulating a real strumming arc
- **Techniques per step** — Normal, Mute (shortened note duration), Harmonic, Slap; each with independent KeySwitch/CC configuration
- **KeySwitch / CC mapping** — Configure which MIDI note or CC each technique sends, on which channel, and how many ticks before the strum — compatible with Ample Sound's default layout out of the box
- **Import / Export** — JSON and plain-text formats; export to clipboard for sharing
- **Tooltips** — Every control has a hover tooltip explaining its function

---

## Requirements

Install both via **Extensions → ReaPack → Browse packages**:

| Package | Author |
|---|---|
| **ReaImGui** | cfillion |
| **js_ReaScriptAPI** | juliansader |

---

## Installation

1. Download `Strummer.lua`
2. Place it anywhere inside your REAPER `Scripts` folder
3. In REAPER: **Actions → Load ReaScript** → select the file
4. Optionally bind it to a shortcut key or toolbar button

---

## Quick Start

1. Create a MIDI item and draw in some chords (notes that start at the same time = one chord block)
2. Open Strummer, pick a pattern from the Library panel
3. Select your MIDI item in the arrange view
4. Click **Apply to Selected MIDI** — the script rewrites the item's notes as a strummed pattern

---

## Usage

### Modes

**Chord Mode** uses whatever notes you drew exactly as written.

**Guitar Mode** remaps your notes to a realistic six-string voicing:
- Multiple notes → mapped across the six strings in pitch order
- Single note → treated as a root; Strummer builds a full chord using the selected chord type (Major, Minor, Dom7, Maj7, Sus2, Power5, etc.)

### Pattern Grid

Each cell represents one rhythmic subdivision. Click to select; right-click to toggle on/off.

| Display | Meaning |
|---|---|
| `v` / `^` | Down strum / Up strum |
| `0–100%` | Velocity scale for this step |
| `Nrm / Mut / Hrm / Slp` | Playing technique |
| `x2`, `x3`… | Step span (occupies multiple base units) |

When a step is selected, the editor below lets you adjust velocity, time offset, technique, and span.

### Step Unit

The **Step unit** row at the top of the grid sets the base duration of every cell:

| Button | Each step = | Typical use |
|---|---|---|
| `1/4` | Quarter note | Slow ballads |
| `1/8` | Eighth note | Most pop/rock patterns |
| `1/16` | Sixteenth note | Funk, detailed rhythms |
| `1/32` | 32nd note | Very dense patterns |
| `1/6` | Eighth triplet | Swing, shuffle |
| `1/12` | 16th triplet | Latin, jazz |

To represent a quarter note in a 1/16 grid: activate a step, leave the next three steps silent.

### Per-step Span

Select a step and use the **Step span** buttons (×1 ×2 ×3 ×4 ×6 ×8) to make that step occupy multiple base units. The cell widens proportionally in the grid. Useful when a pattern has mostly 1/16 steps but needs an occasional quarter note without switching the global grid.

### Humanization

| Parameter | Effect |
|---|---|
| Time Rand | Random timing scatter per note (ticks). Recommended: 5–12 |
| Vel Rand | Random velocity scatter per note. Recommended: 8–15 |
| Strum Speed | Tick gap between successive strings. Recommended: 3–8 |

### KeySwitch / CC Mapping

Open the **KeySwitch/CC** panel to configure what fires before each technique:

- **None** — no extra MIDI event
- **KS Note** — sends a short note on a specified channel N ticks before the strum
- **CC** — sends a Control Change message before the strum

Default configuration matches Ample Sound's standard layout:
- Harmonic → `C-1` (MIDI 0), Channel 1
- Slap → `D-1` (MIDI 2), Channel 1

### Saving Your Own Patterns

1. Edit any pattern in the grid
2. Open **Import/Export → Save to User Library**
3. Patterns are saved automatically to `<REAPER resource dir>/Scripts/Strummer_userdata.json` and reloaded on startup

To delete a user pattern: open **Library**, switch to the `[User]` filter, click **Del**.

### Import Format

Paste into the **Import/Export** panel:

**Text format:**
```
# name: My Pattern
# genre: Custom
# timesig: 4/4
# subdivisions: 16
D,1.00,0,normal,1
-,0.00,0,normal,1
D,0.80,0,mute,2
U,0.60,4,normal,1
```

Each step: `direction, velocity, time offset, technique, span`
- Direction: `D` (down), `U` (up), `-` (silent)
- Technique: `normal`, `mute`, `harmonic`, `slap`
- Span: integer ≥ 1 (optional, defaults to 1)

**JSON format:**
```json
{
  "name": "My Pattern",
  "genre": "Custom",
  "timesig": [4, 4],
  "subdivisions": 16,
  "bars": 1,
  "steps": [
    {"on": true,  "dir": "D", "vel": 1.0, "offset": 0, "tech": "normal", "span": 1},
    {"on": false, "dir": "D", "vel": 0.0, "offset": 0, "tech": "normal", "span": 1},
    {"on": true,  "dir": "D", "vel": 0.8, "offset": 0, "tech": "mute",   "span": 2}
  ]
}
```

> **Note on `timesig` and `bars`**: these fields are metadata for human reference only. Timing is determined entirely by `subdivisions` and per-step `span`.

> **Ableton .agr files**: `.agr` is a proprietary binary format. Recommended workflow: drag the groove back onto a MIDI clip in Ableton → export as `.mid` → convert with a MIDI-to-JSON tool → paste JSON here.

---

## Built-in Pattern Library

| Genre | Patterns |
|---|---|
| Pop | Basic 4/4, Lyric 4/4, Ballad 4/4, 16th Drive |
| Rock | Power 4/4, 16th 4/4, Metal Gallop, Hard Rock Chug |
| Jazz | Swing 4/4, Bossa 2bar, Comping 2bar |
| Blues | Shuffle, 12bar Feel |
| Funk | 16th Groove, Clav 4/4 |
| Folk | Waltz 3/4, Country 2-Step, Boom-Chuck, Bluegrass Flatpick |
| Reggae | Skank 4/4, Ska Upstroke |
| Latin | Samba 2bar, Cumbia 4/4 |
| World | Flamenco Buleria, Flamenco Rumba, Harp Harmonics |

---

## How It Works

1. Reads all MIDI notes in the selected item; groups notes starting within 10 ticks of each other into chord blocks
2. For each chord block, applies the selected pattern repeatedly for the block's duration
3. All original notes are deleted and replaced with strummed output
4. The entire operation is a single undo step

---

## Contributing

Pull requests are welcome, especially:
- New rhythm patterns (add to `PATTERN_LIBRARY` in the script, or submit as a standalone JSON file)
- Guitar voicing improvements for edge cases
- Bug fixes

---

## License

MIT — do whatever you like with it.

---

## Acknowledgements

The design and musical decisions in this project are my own. A significant portion of the code was written with assistance from [Claude](https://claude.ai) (Anthropic). I think it's worth being transparent about that — AI-assisted development is becoming a normal part of building tools like this, and in this case it genuinely accelerated the ReaImGui boilerplate, the JSON parser, and the persistence layer. The guitar voicing logic, pattern library curation, and overall direction involved quite a bit of iteration to get right.
