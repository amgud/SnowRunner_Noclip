# SnowRunner mappings

These are my structure notes from reversing SnowRunner on:

**Patch 18.0 (Season 8) - `1.148111.SNOW_DLC8`**

## 1. Global singletons & master arrays

These are the static pointers that locate objects in the world.

- **`"SnowRunner.exe" + 2E5DA18`** -> `TRUCK_CONTROL` Singleton
  - `+ 0x8` -> Current active Vehicle Object *(the truck you are driving)*

- **`"SnowRunner.exe" + 2E5DA08`** -> `DRIVE_LOGIC` Singleton
  - `+ 0x20` -> Also points to the Current active Vehicle Object

- **`"SnowRunner.exe" + 2E6FC40`** -> Global Spawned Vehicle Array (`std::vector`)
  - `+ 0x40` -> Vehicle Index 0
  - `+ 0x48` -> Vehicle Index 1
  - `+ 0x50` -> Vehicle Index 2... *(and so on. Every `+8` bytes is the next spawned vehicle on the map.)*

## 2. The vehicle object (`[VehObj]`)

This is the root structure of the truck (e.g., `[[2E5DA18] + 0x8]`).

### Internal ID & strings

- `[VehObj] + 0xCE8` -> Vehicle Internal ID String *(e.g., `s_tayga_6436` or `s_khan_lo4f`)*

### Master arrays (`std::vector`)

- `[VehObj] + 0x1E0` -> Master Addons Physics Array (Start) *(Holds addon-related objects/models.)*
  - `+ 0x1E8` -> Array (End)
  - `+ 0x1F0` -> Array (Capacity End)

- `[VehObj] + 0x1F8` -> Master Wheels Array (Start) *(Pointers to `TRUCK_WHEEL_MODEL`)*
  - `+ 0x200` -> Array (End)
  - `+ 0x208` -> Array (Capacity End)

### Visual / render coordinates

These update the camera and graphics.

- `[VehObj] + 0x8EC` -> Visual X Coordinate
- `[VehObj] + 0x8F0` -> Visual Y Coordinate (Altitude)
- `[VehObj] + 0x8F4` -> Visual Z Coordinate

## 3. The addon manager (`TRUCK_ADDON_MODEL`)

The game treats engines, fuel tanks, and cranes as "addons" attached to the base frame.

- **`[VehObj] + 0x58`** -> `TRUCK_ADDON_MODEL` Pointer

### Inside the Addon Manager (`[[VehObj] + 0x58]`)

- `+ 0xCC` -> Visual X Coordinate for Cabin/Chassis

- `+ 0x498` -> Visual Cabin/Chassis Base Pointer\
  *(Better practical sync target than `+0xCC` for cabin/chassis visual movement.)*
  - `+ 0x80` -> Visual Position X
  - `+ 0x84` -> Visual Position Y
  - `+ 0x88` -> Visual Position Z

- `+ 0x568` -> Current Fuel
- `+ 0x56C` -> Fuel Capacity (Max Fuel)
- `+ 0x570` -> Fuel Capacity (Max Fuel)\
  *(This is the field the UI code path actually uses as Max Fuel.)*

- `+ 0x1F8` -> Linked Mechanical Element Pointer Array (or Kinematic Joints Array?) (`std::vector<Element*>`)\
  *(Entry size = 8 bytes. Holds the master list of mechanical element objects used by this addon manager. Empirically seems like 11 entries on tested truck (`s_tayga_6436` with tunings (e.g. Small Crane, Saddle Low)). Every entry becomes active during steering/crane movement.)*
  - `+ 0x200` -> Array (End)
  - `+ 0x208` -> Array (Capacity End)

- `+ 0x210` -> Linked Mechanical Runtime Record Array (or Kinematic Pistons/Actuators Array?) (`std::vector<RuntimeRecord>`)\
  *(Entry size = 0x20 bytes. Acts as the runtime/helper layer built around the `+0x1F8` mechanical elements. Empirically seems like 44 entries on tested truck = exactly 4 runtime entries per `+0x1F8` element.)*
  - `+ 0x218` -> Array (End)
  - `+ 0x220` -> Array (Capacity End)

## 4. Havok physics engine (`hkpRigidBody`)

This is the absolute master of physical movement, gravity, and collision.

- **`[VehObj] + 0x5C8`** -> Main Cabin / Chassis `hkpRigidBody`

### The simulation island

The array of all connected truck parts.

- `[hkpRigidBody] + 0x128` -> `hkpSimulationIsland` Pointer
  - `[Island] + 0x60` -> Array Start (Pointers to every `hkpRigidBody` part of the truck)
  - `[Island] + 0x68` -> Total number of parts (Integer)

### Inside ANY `hkpRigidBody` (Chassis, Wheels, Addons)

*(These offsets apply to the main truck `5C8`, AND every single pointer inside the Island Array).*

#### Directional vectors (3x3 matrix)

- `+ 0x170, 0x174, 0x178` -> Local Forward Vector (X, Y, Z) *(Axis of Roll)*
- `+ 0x180, 0x184, 0x188` -> Local Up Vector (X, Y, Z) *(Axis of Yaw)*
- `+ 0x190, 0x194, 0x198` -> Local Right Vector (X, Y, Z) *(Axis of Pitch)*

#### World coordinates

- `+ 0x1A0, 0x1A4, 0x1A8` -> `hkTransform` (Main Master Position)
- `+ 0x1B0, 0x1B4, 0x1B8` -> Swept Position T0 (Current Start-of-frame Location)
- `+ 0x1C0, 0x1C4, 0x1C8` -> Swept Position T1 (Predicted End-of-frame Location)

#### Motion reference slots

*(Slot A is processed every 4th update. Slot B is processed every 16th update.)*

- `+ 0x250, 0x254, 0x258` -> Motion Reference Position Slot A (`hkVector4`)
- `+ 0x260, 0x264, 0x268` -> Motion Reference Position Slot B (`hkVector4`)
- `+ 0x270` -> Packed Motion Reference Rotation Slot A *(4 Bytes / Hex)*
- `+ 0x274` -> Packed Motion Reference Rotation Slot B *(4 Bytes / Hex)*
  - Packed format note: Source float quaternion order is `X, Y, Z, W`, but Cheat Engine hex display appears as `WZYX`.

#### World rotation (quaternions X,Y,Z,W)

- `+ 0x1D0, 0x1D4, 0x1D8, 0x1DC` -> Swept Rotation T0 (Current)
- `+ 0x1E0, 0x1E4, 0x1E8, 0x1EC` -> Swept Rotation T1 (Predicted)

#### Velocities & forces

- `+ 0x230` -> Linear Velocity X (Momentum)
- `+ 0x234` -> Linear Velocity Y (Gravity / Falling Speed)
- `+ 0x238` -> Linear Velocity Z (Momentum)
- `+ 0x240` -> Angular Velocity Pitch (Torque around Right Vector)
- `+ 0x244` -> Angular Velocity Yaw (Torque around Up Vector)
- `+ 0x248` -> Angular Velocity Roll (Torque around Forward Vector)

## 5. The engine object

This is the real gameplay engine damage object.

- **`[VehObj] + 0x140`** -> Gearbox Damage Stat Object
- **`[VehObj] + 0x148`** -> Engine Damage Stat Object

### Inside the Damage Stat Object

- `+ 0x38` -> Current Object Damage *(4 Bytes / Integer)*
- `+ 0x3C` -> Max Object Damage / Max Health *(4 Bytes / Integer)*

*Freeze `+0x38` at `0` to prevent object damage.*

## 6. The wheel object (`TRUCK_WHEEL_MODEL`)

These are the individual wheels, accessed via pointers inside the Master Wheels Array (`[VehObj] + 0x1F8`).
