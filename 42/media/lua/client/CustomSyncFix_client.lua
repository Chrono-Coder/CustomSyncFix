require "CustomSyncFix_shared"

-- v2: focused on zombies, applying lessons from Physiks DataSync Optimizer:
--   - "inverted threshold" pattern: SNAP big deltas, LERP small ones, IGNORE tiny ones
--     (vanilla was snapping everything, causing the rubber-band the Physiks author called out)
--   - velocity extrapolation: predict where the zombie should be NOW given server snapshot age
--   - pending-lerp queue so we can apply smoothing across a few frames

local SNAP_THRESHOLD = 2.5     -- tiles: above this, snap immediately
local IGNORE_THRESHOLD = 0.2   -- tiles: below this, leave local AI alone
local LERP_FRAMES = 6          -- frames to smooth a medium-delta correction

local pending = {}  -- [id] = { tx, ty, tz, dir, hp, cr, framesLeft, vx, vy }

local function loadSettings()
    CSF.DEBUG = SandboxVars.CustomSyncFix.DebugMode or false
end

local function applyZombieSync(data)
    if not data then return end

    local localPlayer = getPlayer()
    if not localPlayer then return end

    local cell = getCell()
    if not cell then return end
    local zombieList = cell:getZombieList()
    if not zombieList then return end

    local zombieMap = {}
    for i = 0, zombieList:size() - 1 do
        local z = zombieList:get(i)
        if z then zombieMap[z:getOnlineID()] = z end
    end

    local px, py = localPlayer:getX(), localPlayer:getY()
    local toKill = {}

    for i = 1, #data do
        local d = data[i]
        local zombie = zombieMap[d.id]
        if zombie and CSF.withinRange(px, py, d.x, d.y) then
            local cx, cy = zombie:getX(), zombie:getY()
            local dx = d.x - cx
            local dy = d.y - cy
            local dist2 = dx * dx + dy * dy

            if dist2 > SNAP_THRESHOLD * SNAP_THRESHOLD then
                -- Big delta: snap. Vanilla AI was clearly out of sync, just take server truth.
                zombie:setX(d.x)
                zombie:setY(d.y)
                zombie:setZ(d.z)
                zombie:setDirectionAngle(d.dir)
                pending[d.id] = nil
            elseif dist2 > IGNORE_THRESHOLD * IGNORE_THRESHOLD then
                -- Medium delta: queue a lerp so the correction is smooth, not a jerk.
                pending[d.id] = {
                    tx = d.x, ty = d.y, tz = d.z, dir = d.dir,
                    framesLeft = LERP_FRAMES,
                    vx = d.vx or 0, vy = d.vy or 0,
                }
            else
                -- Tiny delta: client AI is close enough. Don't fight it.
            end

            if d.hp ~= nil then zombie:setHealth(d.hp) end
            if d.cr ~= nil then zombie:setCrawler(d.cr) end
            if d.hp and d.hp <= 0 then toKill[#toKill + 1] = zombie end
        end
    end

    for i = 1, #toKill do
        local z = toKill[i]
        if not z:isDead() then z:Kill(nil) end
    end
end

local function applyPending()
    if next(pending) == nil then return end

    local cell = getCell()
    if not cell then return end
    local zombieList = cell:getZombieList()
    if not zombieList then return end

    local zombieMap = {}
    for i = 0, zombieList:size() - 1 do
        local z = zombieList:get(i)
        if z then zombieMap[z:getOnlineID()] = z end
    end

    for id, p in pairs(pending) do
        local z = zombieMap[id]
        if not z then
            pending[id] = nil
        else
            local cx, cy = z:getX(), z:getY()
            local t = 1.0 / p.framesLeft
            local nx = CSF.lerp(cx, p.tx + p.vx, t)
            local ny = CSF.lerp(cy, p.ty + p.vy, t)
            z:setX(nx)
            z:setY(ny)
            z:setZ(p.tz)
            z:setDirectionAngle(CSF.lerpAngle(z:getDirectionAngle(), p.dir, t))
            p.framesLeft = p.framesLeft - 1
            -- advance target by velocity for next frame (predict forward)
            p.tx = p.tx + p.vx
            p.ty = p.ty + p.vy
            if p.framesLeft <= 0 then pending[id] = nil end
        end
    end
end

local function onServerCommand(module, command, args)
    if module ~= CSF.MOD_ID then return end
    if command == CSF.CMD_SYNC_ZOMBIES then
        applyZombieSync(args)
    end
end

local function onTick()
    applyPending()
end

local function onInit()
    loadSettings()
    print("[CSF] Custom Sync Fix v2 client loaded (zombie focus, lerp+extrapolate)")
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.OnInitGlobalModData.Add(onInit)
