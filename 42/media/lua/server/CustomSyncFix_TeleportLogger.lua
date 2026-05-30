-- Server-side teleport detection. Loaded only on the server (this file lives in lua/server/).
-- Logs to coop-console.txt when an entity moves faster than physically plausible.
-- Toggle via sandbox option CustomSyncFix.TeleportLogger.

local STALE_TICKS = 60
local PRUNE_INTERVAL = 600

local lastSeen = {}
local tick = 0
local enabled = false
local threshold = 1.5

local function loadSettings()
    if SandboxVars.CustomSyncFix then
        enabled = SandboxVars.CustomSyncFix.TeleportLogger or false
        threshold = SandboxVars.CustomSyncFix.TeleportThreshold or 1.5
    end
end

local function logTeleport(kind, id, prev, cur, ticks, perTick)
    local dist = math.sqrt((cur.x - prev.x)^2 + (cur.y - prev.y)^2)
    print(string.format(
        "[CSF-TP] %s id=%s  (%.2f,%.2f,%d) -> (%.2f,%.2f,%d)  dist=%.2f over %d ticks (%.2f/tick, threshold=%.2f)",
        kind, tostring(id),
        prev.x, prev.y, prev.z or 0,
        cur.x, cur.y, cur.z or 0,
        dist, ticks, perTick, threshold
    ))
end

local function checkEntity(kind, id, x, y, z)
    local key = kind .. ":" .. tostring(id)
    local prev = lastSeen[key]
    local cur = { x = x, y = y, z = z, tick = tick }
    lastSeen[key] = cur
    if not prev then return end

    local ticks = tick - prev.tick
    if ticks < 1 or ticks > STALE_TICKS then return end

    local dx = x - prev.x
    local dy = y - prev.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local perTick = dist / ticks
    if perTick > threshold then
        logTeleport(kind, id, prev, cur, ticks, perTick)
    end
end

local function scanCell()
    local cell = getCell()
    if not cell then return end

    local zl = cell:getZombieList()
    if zl then
        for i = 0, zl:size() - 1 do
            local z = zl:get(i)
            if z and not z:isDead() then
                checkEntity("ZOMBIE", z:getOnlineID(), z:getX(), z:getY(), z:getZ())
            end
        end
    end

    -- vehicle scan removed: cell:getVehicles() not exposed in B42 Lua binding

    local pl = getOnlinePlayers()
    if pl then
        for i = 0, pl:size() - 1 do
            local p = pl:get(i)
            if p and not p:isDead() then
                checkEntity("PLAYER", p:getOnlineID(), p:getX(), p:getY(), p:getZ())
            end
        end
    end
end

local function pruneOld()
    local cutoff = tick - (STALE_TICKS * 5)
    for key, info in pairs(lastSeen) do
        if info.tick < cutoff then lastSeen[key] = nil end
    end
end

local function onTick()
    if not enabled then return end
    tick = tick + 1
    scanCell()
    if tick % PRUNE_INTERVAL == 0 then pruneOld() end
end

local function onInit()
    loadSettings()
    if enabled then
        print(string.format("[CSF-TP] Teleport logger ENABLED (threshold=%.2f tiles/tick). Grep coop-console.txt for [CSF-TP].", threshold))
    end
end

Events.OnInitGlobalModData.Add(onInit)
Events.OnTick.Add(onTick)
