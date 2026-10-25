# SnowRunner Noclip

A SnowRunner reverse-engineering project focused on building a functional **Noclip / free-flight script** for vehicles.

**Full script tested on Patch 18.0 (Season 8) — `1.148111.SNOW_DLC8`.**

Yes, this is an old game version. It’s simply the version I had lying around on my PC.

## Demo

https://github.com/user-attachments/assets/a6db30a2-8338-43c9-a4e4-99eda691ef7e

## Repository layout

- <kbd>[SnowRunner_Noclip.CT](SnowRunner_Noclip.CT)</kbd> — Minimal table for actual use. Just load it in Cheat Engine and enable the Noclip script.

- <kbd>[SnowRunner_Noclip_debug.CT](SnowRunner_Noclip_debug.CT)</kbd> — Debug/workbench table. Useful if you want to inspect pointers, verify offsets, or continue reversing from where I left off.

- <kbd>[mappings.md](mappings.md)</kbd> — Notes for the structures and offsets that I mapped/reversed.

- <kbd>[src/SnowRunner_Noclip.lua](src/SnowRunner_Noclip.lua)</kbd> — Optional plain-text source copy of the Noclip script for easier readability/diffing.

## Features

- noclip / free-flight movement
- hover/freeze toggle
- tilt / rotation controls
- camera / visual sync
- moves the **whole connected Havok island**, not just one body
- tested with an attached trailer *(without cargo)*

It may also work in co-op, but I did **not** test that, so treat that as a maybe, not a promise.

## Usage

1. Open <kbd>[SnowRunner_Noclip.CT](SnowRunner_Noclip.CT)</kbd>.
2. Enable the Noclip script entry — it will auto-attach to SnowRunner live process.
3. Use the [controls](#controls).

## Controls

### Flight
- <kbd>Ctrl</kbd> + <kbd>Space</kbd> — toggle hover/freeze
- <kbd>Ctrl</kbd> + <kbd>W</kbd> / <kbd>S</kbd> — forward / backward
- <kbd>Ctrl</kbd> + <kbd>A</kbd> / <kbd>D</kbd> — left / right
- <kbd>Ctrl</kbd> + <kbd>Q</kbd> / <kbd>E</kbd> — up / down

### Rotation
- <kbd>Alt</kbd> + <kbd>W</kbd> / <kbd>S</kbd> — pitch
- <kbd>Alt</kbd> + <kbd>A</kbd> / <kbd>D</kbd> — yaw
- <kbd>Alt</kbd> + <kbd>Q</kbd> / <kbd>E</kbd> — roll

### Speed
- <kbd>Ctrl</kbd> + <kbd>1</kbd> — normal speed
- <kbd>Ctrl</kbd> + <kbd>2</kbd> — faster speed

## How it works

The Noclip script is implemented as a Cheat Engine Auto Assembler script with embedded Lua.\
It resolves the current vehicle through the `TRUCK_CONTROL` singleton, grabs the main cabin `hkpRigidBody`, then walks the vehicle’s `hkpSimulationIsland` so all connected rigid bodies move together.

To keep the truck stable and visually synced, it updates:

- Havok world/swept positions
- motion reference slots
- the currently mapped visual transform

It also zeroes relevant velocities when needed, and applies angular velocity when rotating.

So this is not just "teleport one pointer and hope for the best" — it tries to move the whole truck assembly in a way that the game tolerates.

## Compatibility

The complete Noclip behavior was tested on **Patch 18.0 (Season 8) — `1.148111.SNOW_DLC8`**.

Other versions of SnowRunner may have:

- moved singletons
- shifted object layouts
- shifted offsets
- partially matching structures

So if it does not work on your game version, that does **not** automatically mean the whole mapping is useless — it may just need a few updated anchors.

The pointer chain and visual position path have since been re-mapped in a live session on `1.907887.SNOW_DLC_19`. Basic movement with Ctrl+W has been confirmed on that build; hover, rotation, and trailer behavior have not yet been verified.

## Updating for newer versions

<details>
<summary><b>Instructions</b></summary>

\
If you know how to use Cheat Engine and have some experience with it, the Noclip script can be revived for newer versions of the game.

The main starting point is finding and updating the **`TRUCK_CONTROL` singleton**.

I recommend using my [`RTTI Reverse Lookup - Cheat Engine script`](https://github.com/FindMuck/CE_RTTI_Reverse_Lookup) tool, which is a good place to start for re-finding class anchors and singleton paths.\
Also use <kbd>[mappings.md](mappings.md)</kbd>. If only a few offsets shifted, the current mapping notes should still save a lot of time (The Noclip script itself also includes a compact offset map in comments).

General idea:

1. Find the new `TRUCK_CONTROL` singleton (use RTTI tool — `fast start` and `no full-scan` after, should be enough for that).
2. Confirm that:
   - `[TRUCK_CONTROL] + 0x8` still leads to the current active `vehicle object`\
     *(or find the new equivalent)*
3. From that `vehicle object`, verify:
   - the current main `hkpRigidBody` pointer
   - the current addon model and visual transform pointers
   - visual position fields by comparing them while the truck moves
4. Check the Havok rigid body layout:
   - position blocks
   - rotation blocks
   - velocity fields
   - simulation island pointer
5. Update the script offsets accordingly.

</details>

## Known issues

- **Driver arm "spaghetti"**\
  The driver’s arms can stretch in weird ways during noclip. My guess is that the driver's IK (Inverse Kinematics) is not part of the same Havok simulation island and gets pulled back toward the steering wheel by a separate animation controller.

- **Trailer + cargo not fully tested**\
  Trailer attached was tested, but not with every possible addon/cargo combination.

## Reverse-engineering notes

This was my attempt at dynamically reversing parts of SnowRunner’s internal structures and turning that work into a usable Noclip script.

Main tools/methods used:

- [`RTTI Reverse Lookup - Cheat Engine script`](https://github.com/FindMuck/CE_RTTI_Reverse_Lookup)
- Cheat Engine "Structure dissect"
- manual pointer chasing and structure validation
- Cheat Engine "Memory Viewer" + disassembler
- manual assembly/code-path investigation
- "what accesses this address"
- "what writes to this address"
- pointermap / pointerscan comparison

The "compare pointermap pointerscan" technique for finding stable candidates came from this [video](https://www.youtube.com/watch?v=rBe8Atevd-4).

## Related projects

While writing this README I found out there are other SnowRunner projects that also document parts of the game or modify vehicle behavior:

- [Ferrster/Snowrunner-Manual-Gearbox-Mod](https://github.com/Ferrster/Snowrunner-Manual-Gearbox-Mod)
- [drafty46/SMT](https://github.com/drafty46/SMT)
- [NakedDevA/SnowFlyer2](https://github.com/NakedDevA/SnowFlyer2)

I was not aware of them while doing this mapping work.\
They may cover overlapping areas, different areas, or just different game versions. So if you are researching the game further, they are worth checking out too.
