require "CustomSyncFix_shared"

-- v2: focused on zombies, applying lessons from Physiks DataSync Optimizer:
--   - per-player proximity batching (no global broadcast)
--   - rolling 3-frame velocity averaging for extrapolation
--   - LRU cap on lastZombieStates to prevent unbounded growth
--   - adaptive tick throttling under load
--   - velocity included in payload so clients can extrapolate forward

local VELOCITY_FRAMES = 3        -- rolling average window
local STATE_CAP = 1024            -- max tracked zombies before LRU eviction
local LOAD_HEAVY_THRESHOLD = 250  -- if candidate count exceeds this, throttle
local LOAD_THROTTLE_MULT = 2      -- multiply UPDATE_INTERVAL by this under load

local tickCounter = 0
local lastZombieStates = {}       -- { [id] = { x, y, z, dir, hp, cr, vx, vy, vhist={...}, lastSeenTick } }
local stateCount = 0              -- maintained alongside lastZombieStates for O(1) size check

local function loadSettings()
    CSF.UPDATE_INTERVAL = SandboxVars.CustomSyncFix.UpdateInterval or CSF.UPDATE_INTERVAL
    CSF.SYNC_DISTANCE = SandboxVars.CustomSyncFix.SyncDistance or CSF.SYNC_DISTANCE
    CSF.SYNC_ZOMBIES = SandboxVars.CustomSyncFix.SyncZombies
    if CSF.SYNC_ZOMBIES == nil then CSF.SYNC_ZOMBIES = true end
    CSF.MAX_ZOMBIES = SandboxVars.CustomSyncFix.MaxZombies or CSF.MAX_ZOMBIES
    CSF.DEBUG = SandboxVars.CustomSyncFix.DebugMode or false
end

local function stateChanged(cur, prev, epsilon)
    if not prev then return true end
    local dx = cur.x - prev.x
    local dy = cur.y - prev.y
    if (dx * dx + dy * dy) > epsilon * epsilon then return true end
    if math.abs((cur.dir or 0) - (prev.dir or 0)) > 2.0 then return true end
    if cur.hp ~= nil and prev.hp ~= nil and math.abs(cur.hp - prev.hp) > 0.05 then return true end
    if cur.cr ~= prev.cr then return true end
    return false
end

local function buildPlayerPositions(players)
    local positions = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            positions[#positions + 1] = {
                player = p,
                x = p:getX(),
                y = p:getY(),
            }
        end
    end
    return positions
end

local function nearAnyPlayer(x, y, positions, range2)
    for i = 1, #positions do
        local dx = x - positions[i].x
        local dy = y - positions[i].y
        if (dx * dx + dy * dy) <= range2 then return true end
    end
    return false
end

-- LRU-style eviction: drop the oldest-seen entries when over cap
local function pruneByLRU()
    if stateCount <= STATE_CAP then return end
    local entries = {}
    for id, st in pairs(lastZombieStates) do
        entries[#entries + 1] = { id = id, t = st.lastSeenTick or 0 }
    end
    table.sort(entries, function(a, b) return a.t < b.t end)
    local toRemove = stateCount - STATE_CAP
    for i = 1, toRemove do
        lastZombieStates[entries[i].id] = nil
        stateCount = stateCount - 1
    end
end

-- Append new sample to history and return smoothed velocity over the window
local function pushVelocitySample(prev, vx, vy)
    local hist = prev.vhist
    if not hist then hist = {}; prev.vhist = hist end
    hist[#hist + 1] = { vx = vx, vy = vy }
    while #hist > VELOCITY_FRAMES do table.remove(hist, 1) end
    local sx, sy = 0, 0
    for i = 1, #hist do sx = sx + hist[i].vx; sy = sy + hist[i].vy end
    local n = #hist
    return sx / n, sy / n
end

local function collectCandidates(positions, range2, ticksElapsed)
    local cell = getCell()
    if not cell then return nil end
    local zombieList = cell:getZombieList()
    if not zombieList then return nil end

    local candidates = {}
    for i = 0, zombieList:size() - 1 do
        local z = zombieList:get(i)
        if z and not z:isDead() then
            local zx, zy = z:getX(), z:getY()
            if nearAnyPlayer(zx, zy, positions, range2) then
                local id = z:getOnlineID()
                local zz = z:getZ()
                local dir = z:getDirectionAngle()
                local hp = z:getHealth()
                local cr = z:isCrawling()

                local prev = lastZombieStates[id]
                local cur = { x = zx, y = zy, z = zz, dir = dir, hp = hp, cr = cr, lastSeenTick = tickCounter }

                if stateChanged(cur, prev, CSF.ZOMBIE_DELTA_EPSILON) then
                    local vx, vy = 0, 0
                    if prev and ticksElapsed > 0 then
                        local rawVx = (zx - prev.x) / ticksElapsed
                        local rawVy = (zy - prev.y) / ticksElapsed
                        vx, vy = pushVelocitySample(prev, rawVx, rawVy)
                    elseif prev and prev.vhist then
                        cur.vhist = prev.vhist
                    end

                    cur.vx = vx
                    cur.vy = vy

                    local minDist2 = math.huge
                    for j = 1, #positions do
                        local d = CSF.distSq(zx, zy, positions[j].x, positions[j].y)
                        if d < minDist2 then minDist2 = d end
                    end

                    candidates[#candidates + 1] = {
                        id = id, x = zx, y = zy, z = zz, dir = dir,
                        hp = hp, cr = cr, vx = vx, vy = vy,
                        dist2 = minDist2,
                    }

                    if not prev then stateCount = stateCount + 1 end
                    lastZombieStates[id] = cur
                elseif prev then
                    prev.lastSeenTick = tickCounter
                end
            end
        end
    end

    return candidates
end

-- Send each player only the zombies relevant to THEIR position
local function sendPerPlayer(positions, candidates)
    if #candidates == 0 then return end

    -- Sort candidates by global "closeness to any player" once for fair MAX_ZOMBIES truncation
    if #candidates > CSF.MAX_ZOMBIES then
        table.sort(candidates, function(a, b) return a.dist2 < b.dist2 end)
    end
    local globalLimit = math.min(#candidates, CSF.MAX_ZOMBIES)

    local range2 = CSF.SYNC_DISTANCE * CSF.SYNC_DISTANCE
    local sent = 0

    for pi = 1, #positions do
        local p = positions[pi]
        local data = {}
        for ci = 1, globalLimit do
            local c = candidates[ci]
            local dx = c.x - p.x
            local dy = c.y - p.y
            if (dx * dx + dy * dy) <= range2 then
                data[#data + 1] = {
                    id = c.id, x = c.x, y = c.y, z = c.z,
                    dir = c.dir, hp = c.hp, cr = c.cr,
                    vx = c.vx, vy = c.vy,
                }
            end
        end
        if #data > 0 then
            sendServerCommand(p.player, CSF.MOD_ID, CSF.CMD_SYNC_ZOMBIES, data)
            sent = sent + #data
        end
    end

    if CSF.DEBUG then
        print(string.format("[CSF] sent %d zombie states across %d players (of %d global candidates)",
            sent, #positions, #candidates))
    end
end

local function cleanupCaches()
    local cell = getCell()
    if not cell then return end

    local liveZombies = {}
    local zombieList = cell:getZombieList()
    if zombieList then
        for i = 0, zombieList:size() - 1 do
            local z = zombieList:get(i)
            if z then liveZombies[z:getOnlineID()] = true end
        end
    end

    for id in pairs(lastZombieStates) do
        if not liveZombies[id] then
            lastZombieStates[id] = nil
            stateCount = stateCount - 1
        end
    end

    pruneByLRU()
end

local lastSentTick = 0
local function onTick()
    tickCounter = tickCounter + 1

    if tickCounter % 300 == 0 then cleanupCaches() end
    if not CSF.SYNC_ZOMBIES then return end

    local players = getOnlinePlayers()
    if players:size() < 2 then return end

    -- Adaptive throttling: under load, scale back our update rate
    local interval = CSF.UPDATE_INTERVAL
    if stateCount > LOAD_HEAVY_THRESHOLD then
        interval = interval * LOAD_THROTTLE_MULT
    end

    if (tickCounter - lastSentTick) < interval then return end
    local ticksElapsed = tickCounter - lastSentTick
    lastSentTick = tickCounter

    local positions = buildPlayerPositions(players)
    if #positions < 2 then return end

    local range2 = CSF.SYNC_DISTANCE * CSF.SYNC_DISTANCE
    local candidates = collectCandidates(positions, range2, ticksElapsed)
    if not candidates then return end

    sendPerPlayer(positions, candidates)
end

local function onInit()
    loadSettings()
    print(string.format(
        "[CSF] Custom Sync Fix v2 (zombie-focused) loaded - interval=%d, dist=%d, max=%d, stateCap=%d",
        CSF.UPDATE_INTERVAL, CSF.SYNC_DISTANCE, CSF.MAX_ZOMBIES, STATE_CAP))
end

Events.OnInitGlobalModData.Add(onInit)
Events.OnTick.Add(onTick)
