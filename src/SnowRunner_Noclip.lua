[ENABLE]
{$lua}
if syntaxcheck then return end

-- Known issue: driver's arms stretch into "spaghetti". His IK (Inverse Kinematics) skeleton is likely not inside the hkpSimulationIsland array. His skeleton is likely handled by a completely separate animation controller that slowly interpolates his hands back to the steering wheel...

--[[==============================================================================
  SNOWRUNNER NOCLIP - MEMORY STRUCTURE & POINTER MAP
  ==============================================================================
  GAME VERSION: Patch 18.0 (Season 8) - 1.148111.SNOW_DLC8

  BASE POINTER:
  "SnowRunner.exe"+2E5DA18       -> TRUCK_CONTROL Singleton
  ["SnowRunner.exe"+2E5DA18] + 8 -> Current active Vehicle Object

  VISUAL MODEL COORDINATES (Updates the camera/visual model):
  [VehObj + 0x8EC] -> Visual X (Float)
  [VehObj + 0x8F0] -> Visual Y (Float) [Altitude]
  [VehObj + 0x8F4] -> Visual Z (Float)

  ADDON MANAGER VISUAL BASE (Better practical sync target for cabin/chassis visuals):
  [VehObj + 0x58]    -> TRUCK_ADDON_MODEL Pointer
  [AddonMgr + 0x498] -> Visual Cabin/Chassis Base Pointer
  [BasePtr + 0x80]   -> Visual Position X
  [BasePtr + 0x84]   -> Visual Position Y
  [BasePtr + 0x88]   -> Visual Position Z

  HAVOK PHYSICS ENGINE (hkpRigidBody & hkpSimulationIsland):
  [VehObj + 0x5C8]  -> Main Cabin/Chassis Physics Object (hkpRigidBody)
  [CabinRb + 0x128] -> Physics Simulation Island (hkpSimulationIsland)
                          (The island contains all rigid bodies connected to the truck)
  [Island + 0x60]   -> Array of connected rigid body pointers
  [Island + 0x68]   -> Number of connected entities (Integer)

  HAVOK RIGID BODY OFFSETS (Inside each hkpRigidBody):
  -- Matrix 3x3 (Directional Vectors)
  + 0x170, 0x174, 0x178 -> Local Forward Vector (X, Y, Z) [Used for Roll]
  + 0x190, 0x194, 0x198 -> Local Right Vector (X, Y, Z) [Used for Pitch]

  -- World Coordinates (Must be updated together to bypass physics interpolation)
  + 0x1A0, 0x1A4, 0x1A8 -> hkTransform Position (Main Anchor) (X, Y, Z)
  + 0x1B0, 0x1B4, 0x1B8 -> Swept Position T0 (Current location)
  + 0x1C0, 0x1C4, 0x1C8 -> Swept Position T1 (Predicted next frame location)
  -- Motion Reference Slots
  -- Slot A is processed every 4th update. Slot B is processed every 16th update.
  + 0x250, 0x254, 0x258 -> Motion Reference Position Slot A (hkVector4)
  + 0x260, 0x264, 0x268 -> Motion Reference Position Slot B (hkVector4)

  -- World Rotation (Quaternions X, Y, Z, W - Must be mathematically valid!)
  + 0x1D0, 0x1D4, 0x1D8, 0x1DC -> Swept Rotation T0 (Current rotation)
  + 0x1E0, 0x1E4, 0x1E8, 0x1EC -> Swept Rotation T1 (Predicted next frame rotation)

  -- Velocity & Forces (Zero these out to create absolute Freezes/Brakes)
  + 0x230, 0x234, 0x238 -> Linear Velocity (X = Momentum, Y = Gravity/Falling, Z = Momentum)
  + 0x240, 0x244, 0x248 -> Angular Velocity / Torque (Pitch, Yaw, Roll)
=================================================================================]]--

local function scheduleDisable()
  if disableQueued then return end
  disableQueued = true
  if memrec then
    local mr = memrec
    local t = createTimer(nil, false)
    t.Interval = 1
    t.OnTimer = function(timer)
      timer.destroy()
      if mr then mr.Active = false end
    end
    t.Enabled = true
  end
end

local function autoAttachSnowRunner()
  local pid = getProcessIDFromProcessName('SnowRunner.exe')
  if pid == nil or pid == 0 then
    messageDialog(
      'SnowRunner.exe is not running.',
      mtWarning,
      mbOK
    )
    error('SnowRunner.exe is not running.')
  end

  if getOpenedProcessID() ~= pid then
    openProcess(pid)
    reinitializeSymbolhandler()
  end
end

autoAttachSnowRunner()

if NCTimer ~= nil then NCTimer.destroy(); NCTimer = nil end
if freezeKey ~= nil then freezeKey.destroy(); freezeKey = nil end
if speed1Key ~= nil then speed1Key.destroy(); speed1Key = nil end
if speed2Key ~= nil then speed2Key.destroy(); speed2Key = nil end

disableQueued = false
isFrozen = false
targetY = nil
frozenRot = {}
globalSpeedMult = 1.0
wasTilting = false
lastVehObj = nil
lastCabinRb = nil
lastIsland = nil
lastEntityArray = nil
lastNumEntities = nil
rbCache = {}
rbCacheCount = 0

-- Cache the static address once instead of resolving the symbol every tick
truckCtlStatic = getAddressSafe('SnowRunner.exe+2E5DA18')
lastTick = getTickCount()

local MOVE_EPS = 0.0001
local QUAT_EPS2 = 1e-8

local function moveXYZBlock(rb, offset, moveX, deltaY, moveZ)
  local x = readFloat(rb + offset)
  local y = readFloat(rb + offset + 0x4)
  local z = readFloat(rb + offset + 0x8)

  if x ~= nil and y ~= nil and z ~= nil then
    writeFloat(rb + offset,         x + moveX)
    writeFloat(rb + offset + 0x4,   y + deltaY)
    writeFloat(rb + offset + 0x8,   z + moveZ)
  end
end

local function moveVisualXYZ(vehObj, moveX, deltaY, moveZ)
  local vx = readFloat(vehObj + 0x8EC)
  local vy = readFloat(vehObj + 0x8F0)
  local vz = readFloat(vehObj + 0x8F4)

  if vx ~= nil and vy ~= nil and vz ~= nil then
    writeFloat(vehObj + 0x8EC, vx + moveX)
    writeFloat(vehObj + 0x8F0, vy + deltaY)
    writeFloat(vehObj + 0x8F4, vz + moveZ)
  end
end

local function moveVisualBaseNode(vehObj, moveX, deltaY, moveZ)
  local addonMgr = readPointer(vehObj + 0x58)
  if addonMgr == nil or addonMgr == 0 then return end

  local baseNode = readPointer(addonMgr + 0x498)
  if baseNode == nil or baseNode == 0 then return end

  local x = readFloat(baseNode + 0x80)
  local y = readFloat(baseNode + 0x84)
  local z = readFloat(baseNode + 0x88)

  if x ~= nil and y ~= nil and z ~= nil then
    writeFloat(baseNode + 0x80, x + moveX)
    writeFloat(baseNode + 0x84, y + deltaY)
    writeFloat(baseNode + 0x88, z + moveZ)
  end
end

local function rebuildRigidBodyCache(entityArray, numEntities)
  local newCache = {}
  local newCount = 0

  for i = 0, numEntities - 1 do
    local rb = readPointer(entityArray + (i * 8))
    if rb ~= nil and rb ~= 0 then
      newCount = newCount + 1
      newCache[newCount] = rb
    end
  end

  rbCache = newCache
  rbCacheCount = newCount

  return rbCacheCount > 0
end

-- HOVER TOGGLE (Ctrl + Space)
freezeKey = createHotkey(function()
  isFrozen = not isFrozen
  if not isFrozen then
    targetY = nil
    frozenRot = {}
    wasTilting = false
  end
end, 0x20, 0x11)

-- SPEED MODIFIERS (Ctrl + 1 / Ctrl + 2)
speed1Key = createHotkey(function()
  globalSpeedMult = 1.0
end, 0x31, 0x11) -- 0x31 = '1' key
speed2Key = createHotkey(function()
  globalSpeedMult = 2.0
end, 0x32, 0x11) -- 0x32 = '2' key

NCTimer = createTimer(nil)
NCTimer.Interval = 15 -- 60fps update rate

NCTimer.OnTimer = function(t)
  local pid = getProcessIDFromProcessName('SnowRunner.exe')
  if pid == nil or pid == 0 then
    scheduleDisable()
    return
  end

  -- Time-based movement so speed stays stable even if the timer jitters
  local now = getTickCount()
  local dt = (now - lastTick) * 0.001
  lastTick = now
  if dt <= 0 or dt > 0.05 then dt = 0.015 end

  local isCtrl = isKeyPressed(0x11)
  local isAlt = isKeyPressed(0x12)

  local doY, doXZ, doTilt = false, false, false
  local dY, moveFwd, moveRgt = 0, 0, 0
  local pitchSpeed, yawSpeed, rollSpeed = 0, 0, 0

  local inputY, inputFwd, inputRgt = 0, 0, 0
  local inputPitch, inputYaw, inputRoll = 0, 0, 0

  -- Apply Speed Multipliers
  local speed = 33.3333333333 * dt * globalSpeedMult
  local rotPower = 100.0 * dt * globalSpeedMult

  -- FLIGHT CONTROLS (Ctrl + WASD/QE)
  if isCtrl then
    if isKeyPressed(0x51) then inputY = inputY + 1 end      -- Q : Up
    if isKeyPressed(0x45) then inputY = inputY - 1 end      -- E : Down
    if isKeyPressed(0x57) then inputFwd = inputFwd - 1 end  -- W : Forward
    if isKeyPressed(0x53) then inputFwd = inputFwd + 1 end  -- S : Backward
    if isKeyPressed(0x41) then inputRgt = inputRgt + 1 end  -- A : Left
    if isKeyPressed(0x44) then inputRgt = inputRgt - 1 end  -- D : Right
  end

  -- Normalize horizontal movement so diagonal flight is not faster
  local planarLen = math.sqrt((inputFwd * inputFwd) + (inputRgt * inputRgt))
  if planarLen > MOVE_EPS then
    moveFwd = (inputFwd / planarLen) * speed
    moveRgt = (inputRgt / planarLen) * speed
    doXZ = true
  end

  if inputY ~= 0 then
    dY = inputY * speed
    doY = true
  end

  -- TILT CONTROLS (Alt + WASD/QE)
  if isAlt then
    if isKeyPressed(0x51) then inputRoll = inputRoll + 1 end    -- Q : Roll Left
    if isKeyPressed(0x45) then inputRoll = inputRoll - 1 end    -- E : Roll Right
    if isKeyPressed(0x57) then inputPitch = inputPitch - 1 end  -- W : Nose Down
    if isKeyPressed(0x53) then inputPitch = inputPitch + 1 end  -- S : Nose Up
    if isKeyPressed(0x41) then inputYaw = inputYaw - 1 end      -- A : Spin Left
    if isKeyPressed(0x44) then inputYaw = inputYaw + 1 end      -- D : Spin Right
  end

  if inputPitch ~= 0 or inputYaw ~= 0 or inputRoll ~= 0 then
    pitchSpeed = inputPitch * rotPower
    yawSpeed = inputYaw * rotPower
    rollSpeed = inputRoll * rotPower
    doTilt = true
  end

  -- If Hover Mode is OFF and no keys are pressed, exit and resume normal game physics
  if not isFrozen and not doY and not doXZ and not doTilt then
    targetY = nil
    frozenRot = {}
    wasTilting = false
    return
  end

  if truckCtlStatic == nil then
    truckCtlStatic = getAddressSafe('SnowRunner.exe+2E5DA18')
    if truckCtlStatic == nil then return end
  end

  local base = readPointer(truckCtlStatic)
  if base == nil or base == 0 then return end
  local vehObj = readPointer(base + 0x8)
  if vehObj == nil or vehObj == 0 then return end
  local cabinRb = readPointer(vehObj + 0x5C8)
  if cabinRb == nil or cabinRb == 0 then return end
  local island = readPointer(cabinRb + 0x128)
  if island == nil or island == 0 then return end

  local entityArray = readPointer(island + 0x60)
  local numEntities = readInteger(island + 0x68)
  if entityArray == nil or entityArray == 0 or numEntities == nil or numEntities <= 0 or numEntities > 300 then return end

  -- Rebuild the cached rigid body list only when the active vehicle / island topology changes
  if lastVehObj ~= vehObj or lastCabinRb ~= cabinRb or lastIsland ~= island or lastEntityArray ~= entityArray or lastNumEntities ~= numEntities then
    targetY = nil
    frozenRot = {}
    wasTilting = false

    if not rebuildRigidBodyCache(entityArray, numEntities) then return end

    lastVehObj = vehObj
    lastCabinRb = cabinRb
    lastIsland = island
    lastEntityArray = entityArray
    lastNumEntities = numEntities
  end

  if rbCacheCount <= 0 then return end

  -- ==========================================
  -- MATH PHASE
  -- ==========================================
  -- 1. Delta Altitude Math
  if targetY == nil then targetY = readFloat(cabinRb + 0x1A4) or 0.0 end
  if doY then targetY = targetY + dY end
  local currentY = readFloat(cabinRb + 0x1A4) or targetY
  local deltaY = targetY - currentY
  if math.abs(deltaY) <= MOVE_EPS then deltaY = 0 end

  -- 2. Directional Vectors
  -- We read the true Local Right Vector (0x190 row) for Pitch
  local memRx = readFloat(cabinRb + 0x190) or 1.0
  local memRy = readFloat(cabinRb + 0x194) or 0.0
  local memRz = readFloat(cabinRb + 0x198) or 0.0

  -- We read the true Local Forward Vector (0x170 row) for Roll
  local fwdX = readFloat(cabinRb + 0x170) or 0.0
  local fwdY = readFloat(cabinRb + 0x174) or 0.0
  local fwdZ = readFloat(cabinRb + 0x178) or 1.0

  -- Flatten Right Vector to horizon for pure horizontal flight math
  local len = math.sqrt((memRx * memRx) + (memRz * memRz))
  local Rx, Rz = 1.0, 0.0
  if len > MOVE_EPS then
    Rx = memRx / len
    Rz = memRz / len
  end

  -- Calculate True Forward Vector (Always 90 degrees from Right Vector)
  local Fx = -Rz
  local Fz = Rx

  -- Calculate final map movement offsets
  local moveX, moveZ = 0, 0
  if doXZ then
    moveX = (Fx * moveFwd) + (Rx * moveRgt)
    moveZ = (Fz * moveFwd) + (Rz * moveRgt)

    if math.abs(moveX) <= MOVE_EPS then moveX = 0 end
    if math.abs(moveZ) <= MOVE_EPS then moveZ = 0 end
  end

  -- Calculate Rotation Torque
  local angX, angY, angZ = 0, 0, 0
  if doTilt then
    -- Combine Pitch (around Right), Yaw (around World Up), and Roll (around Forward)
    angX = (memRx * pitchSpeed) + (fwdX * rollSpeed)
    angZ = (memRz * pitchSpeed) + (fwdZ * rollSpeed)
    angY = (memRy * pitchSpeed) + (fwdY * rollSpeed) + yawSpeed
  end

  -- Clear statue lock only when tilt begins
  if doTilt and not wasTilting then
    frozenRot = {}
  end
  wasTilting = doTilt

  local doMove = (deltaY ~= 0) or (moveX ~= 0) or (moveZ ~= 0)

  -- ==========================================
  -- PHYSICS APPLICATION PHASE
  -- ==========================================
  for i = 1, rbCacheCount do
    local rb = rbCache[i]
    if rb ~= nil and rb ~= 0 then

      -- MOVE COORDINATES (Elevator & Horizontal Flight)
      if doMove then
        moveXYZBlock(rb, 0x1A0, moveX, deltaY, moveZ)
        moveXYZBlock(rb, 0x1B0, moveX, deltaY, moveZ)
        moveXYZBlock(rb, 0x1C0, moveX, deltaY, moveZ)
        moveXYZBlock(rb, 0x250, moveX, deltaY, moveZ)
        moveXYZBlock(rb, 0x260, moveX, deltaY, moveZ)
      end

      -- ALWAYS KILL FALLING VELOCITY
      writeFloat(rb + 0x234, 0.0)

      if doTilt then
        -- Leave X/Z Linear Velocity alone so wheels can orbit during spin
        writeFloat(rb + 0x240, angX)
        writeFloat(rb + 0x244, angY)
        writeFloat(rb + 0x248, angZ)
      else
        -- Not rotating: Absolute Zero Velocity
        writeFloat(rb + 0x230, 0.0); writeFloat(rb + 0x238, 0.0)
        writeFloat(rb + 0x240, 0.0); writeFloat(rb + 0x244, 0.0); writeFloat(rb + 0x248, 0.0)

        -- The Ultimate Quaternion Statue Lock
        if frozenRot[rb] == nil then
          local qx = readFloat(rb + 0x1D0)
          local qy = readFloat(rb + 0x1D4)
          local qz = readFloat(rb + 0x1D8)
          local qw = readFloat(rb + 0x1DC)

          if qx ~= nil and qy ~= nil and qz ~= nil and qw ~= nil then
            local qlen2 = (qx*qx) + (qy*qy) + (qz*qz) + (qw*qw)
            if qlen2 > QUAT_EPS2 then
              frozenRot[rb] = {
                x = qx,
                y = qy,
                z = qz,
                w = qw
              }
            end
          end
        else
          local q = frozenRot[rb]
          if q.x ~= nil and q.y ~= nil and q.z ~= nil and q.w ~= nil then
            writeFloat(rb + 0x1D0, q.x); writeFloat(rb + 0x1D4, q.y); writeFloat(rb + 0x1D8, q.z); writeFloat(rb + 0x1DC, q.w)
            writeFloat(rb + 0x1E0, q.x); writeFloat(rb + 0x1E4, q.y); writeFloat(rb + 0x1E8, q.z); writeFloat(rb + 0x1EC, q.w)
          end
        end
      end
    end
  end

  -- ==========================================
  -- CAMERA SYNC
  -- ==========================================
  if doMove then
    moveVisualXYZ(vehObj, moveX, deltaY, moveZ)
    moveVisualBaseNode(vehObj, moveX, deltaY, moveZ)
  end
end
{$asm}

[DISABLE]
{$lua}
if syntaxcheck then return end

-- Clean up and destroy everything when the script is toggled off
if NCTimer ~= nil then NCTimer.destroy(); NCTimer = nil end
if freezeKey ~= nil then freezeKey.destroy(); freezeKey = nil end
if speed1Key ~= nil then speed1Key.destroy(); speed1Key = nil end
if speed2Key ~= nil then speed2Key.destroy(); speed2Key = nil end

-- Clear global locks so game physics resume
disableQueued = false
isFrozen = false
targetY = nil
frozenRot = {}
globalSpeedMult = 1.0
wasTilting = false
lastVehObj = nil
lastCabinRb = nil
lastIsland = nil
lastEntityArray = nil
lastNumEntities = nil
rbCache = {}
rbCacheCount = 0
truckCtlStatic = nil
lastTick = nil
{$asm}
