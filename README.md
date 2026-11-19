# ForeverClasses (Beta-Test)

A lightweight, high-performance personal resource and ability tracking HUD built for **World of Warcraft: Forever** and modern WoW engine builds (10.0+ / 11.0 / 12.0 / Midnight / 1.60.1).

> [!IMPORTANT]
> **Beta Testing & Community Feedback Wanted:**
> **ForeverClasses** is currently in active **Beta-Test**. While core mechanics and classes such as **Rogue**, **Warrior**, **Paladin**, and **Shaman** have been thoroughly refined, classes like **Mage**, **Hunter**, **Druid**, **Priest**, and **Warlock** are still in active testing and have not yet been comprehensively field-tested.
> 
> We are actively looking for player feedback! If you play any of these classes, please report any bugs or suggestions regarding ability tracking, buff durations, or resource display to help us polish every class.

---

## Features

### 1. Dynamic Resource HUD (Phase 1)
- **Health Bar:** Live health status with configurable numeric and percentage text overlays.
- **Class-Colored Health Bar:** Optional setting to tint the health bar by your character's class color.
- **Upcoming Heals (Heal Prediction):** Renders incoming direct and over-time heals seamlessly on the health bar.
- **Dynamic Power Bar:** Automatically detects your active power type with zero combat taint:
  - **Mana (Blue)** for Priests, Mages, Warlocks, Druid casters, Paladins, Shamans, and Hunters.
  - **Rage (Red)** for Warriors and Druid Bear form.
  - **Energy (Yellow)** for Rogues and Druid Cat form.
- **Dynamic Class Crest Minimap Button:** Shows your animated high-resolution class crest orbiting the minimap rim.

### 2. Combat Indicators & Debuffs (Phase 1.5)
- **Rogue / Feral Combo Points:** Crisp circular combo point orbs rendered smoothly beneath the HUD in combat.
- **Harmful Debuffs Tray:** Docked to the right of the HUD, displaying up to 5 harmful combat debuffs with dispel-type colored borders and countdown timers.
- **Debuff Exclusion System:** Filter out non-combat exhaustion or buffs (such as Campfire XP exhaustion) with `/fc ignore <name>`.
- **Low Health Danger Warning:** Full-perimeter crimson border pulse and flashing red alert bar when player health drops to $\le 33\%$ HP (customizable threshold).

### 3. Ability & Cooldown Management Bar (Phase 2)
- **Docked Directly Above Health Bar:** 7-slot customizable tray cleanly centered over your health bar (30×30px icons, 4px gaps, 234px width perfectly framing the 240px health bar).
- **Drag & Drop Customization:** Open your Spellbook (`P`) or bag and drag any spell or item directly onto slots 1–7.
- **Rich Visual States:**
  - **Ready:** Crisp full-color icon.
  - **On Cooldown:** Darkened icon + cooldown spiral sweep + numeric countdown (`24s`, `1.5m`).
  - **Active Buff:** Radiant golden border glow and gold duration countdown while the buff is active on you (*Sprint*, *Evasion*, *Blade Flurry*, etc.).
  - **Out of Mana / Energy:** Subtle blue tint indicator.
  - **GCD:** Smooth spiral sweep without numeric countdown clutter.
  - **Charges / Stacks:** Counter displayed in the bottom-right corner.
  - **Empty / Unassigned:** Displays slot number out of combat; automatically hidden during combat.
- **Modern Engine First:** Fully compatible with modern `C_Spell`, `C_Item`, and `C_UnitAuras` APIs without taint.

---

## Installation

1. Copy the `ForeverClasses` folder into your WoW AddOns directory:
   ```text
   World of Warcraft/_classic_beta_/Interface/AddOns/ForeverClasses
   ```
2. Start the game or type `/reload` if already logged in.
3. Ensure **ForeverClasses** is enabled in your AddOn list.

---

## Slash Commands

You can use standard space-separated commands or instant hyphenated commands:

| Command | Hyphenated Shortcut | Description |
| :--- | :--- | :--- |
| `/fc` | `/fc` | Opens the graphical settings panel. |
| `/fc cd` | `/fc-cds` | Toggles the Ability & Cooldown Bar on/off. |
| `/fc testcd` | `/fc-testcd` | Simulates 7 signature cooldown states for 8 seconds. |
| `/fc listcds` | `/fc-listcds` | Lists abilities and items assigned to slots 1–7. |
| `/fc cd <slot> <spell>` | — | Assigns an ability to a slot (e.g. `/fc cd 1 Kick`). |
| `/fc clearcd <slot>` | — | Clears a slot 1–7 (or Shift-Right-Click the slot icon). |
| `/fc cddebug` | `/fc-cddebug` | Diagnoses live cooldown detection APIs and slot values in chat. |
| `/fc debuffs` | `/fc-debuffs` | Toggles harmful debuff icons display. |
| `/fc testdebuff` | `/fc-testdebuff` | Simulates 3 harmful debuffs for 8 seconds. |
| `/fc ignore <name>` | — | Adds a debuff to the exclusion list (e.g. Campfire exhaustion). |
| `/fc unignore <name>`| — | Removes a debuff from the exclusion list. |
| `/fc lowhealth` | `/fc-low` | Toggles low health danger warning. |
| `/fc threshold <%>` | — | Sets trigger percentage for low health alert (default 33%). |
| `/fc testlow` | `/fc-testlow` | Simulates low health warning pulse for 6 seconds. |
| `/fc cp` | `/fc-cp` | Toggles Rogue circular combo points. |
| `/fc testcp` | `/fc-testcp` | Simulates combo points 1 to 5 CP build up. |
| `/fc classcolor` | `/fc-classcolor` | Toggles class-colored health bar. |
| `/fc icon` | `/fc-icon` | Toggles the class crest minimap button. |
| `/fc heals` | `/fc-heals` | Toggles upcoming heal prediction. |
| `/fc testheal` | `/fc-testheal` | Simulates an incoming heal for 5 seconds. |
| `/fc both` | `/fc-both` | Status text shows both numbers and percentage. |
| `/fc num` | `/fc-num` | Status text shows numeric only. |
| `/fc pct` | `/fc-pct` | Status text shows percentage only. |
| `/fc sync` | `/fc-sync` | Status text syncs with game settings. |
| `/fc none` | `/fc-none` | Hides status text. |
| `/fc lock` | `/fc-lock` | Locks HUD firmly in place. |
| `/fc unlock` | `/fc-unlock` | Unlocks HUD for free movement dragging. |
| `/fc reset` | `/fc-reset` | Resets HUD position to center of screen. |
| `/fc debug` | — | Prints diagnostic information to chat. |
