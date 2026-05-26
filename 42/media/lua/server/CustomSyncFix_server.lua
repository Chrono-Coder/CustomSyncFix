require "CustomSyncFix_shared"

local tickCounter = 0
local lastZombieStates = {}

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
    return false
end

local function buildPlayerPositions(players)
    local positions = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            positions[#positions + 1] = { x = p:getX(), y = p:getY() }
        end
    end
    return positions
end

local function nearAnyPlayer(x, y, positions)
    for i = 1, #positions do
        if CSF.withinRange(x, y, positions[i].x, positions[i].y) then
            return true
        end
    end
    return false
end

local function syncZombies(positions)
    if not CSF.SYNC_ZOMBIES then return end

    local cell = getCell()
    if not cell then return end
    local zombieList = cell:getZombieList()
    if not zombieList then return end

    local candidates = {}
    for i = 0, zombieList:size() - 1 do
        local z = zombieList:get(i)
        if z and not z:isDead() then
            local zx, zy = z:getX(), z:getY()
            if nearAnyPlayer(zx, zy, positions) then
                local id = z:getOnlineID()
                local zz = z:getZ()
                local dir = z:getDirectionAngle()

                local state = { x = zx, y = zy, z = zz, dir = dir }
                if stateChanged(state, lastZombieStates[id], CSF.ZOMBIE_DELTA_EPSILON) then
                    local minDist = math.huge
                    for j = 1, #positions do
                        local d = CSF.distSq(zx, zy, positions[j].x, positions[j].y)
                        if d < minDist then minDist = d end
                    end
                    candidates[#candidates + 1] = {
                        id = id,
                        x = zx, y = zy, z = zz,
                        dir = dir,
                        hp = z:getHealth(),
                        cr = z:isCrawling(),
                        dist = minDist,
                    }
                    lastZombieStates[id] = state
                end
            end
        end
    end

    if #candidates > CSF.MAX_ZOMBIES then
        table.sort(candidates, function(a, b) return a.dist < b.dist end)
    end

    local limit = math.min(#candidates, CSF.MAX_ZOMBIES)
    if limit == 0 then return end

    local data = {}
    for i = 1, limit do
        local c = candidates[i]
        data[#data + 1] = {
            id = c.id,
            x = c.x, y = c.y, z = c.z,
            dir = c.dir,
            hp = c.hp,
            cr = c.cr,
        }
    end

    sendServerCommand(CSF.MOD_ID, CSF.CMD_SYNC_ZOMBIES, data)
    if CSF.DEBUG then
        print("[CSF] Sent zombie sync: " .. #data .. " (of " .. #candidates .. " candidates)")
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
        if not liveZombies[id] then lastZombieStates[id] = nil end
    end
end

local function onTick()
    tickCounter = tickCounter + 1

    if tickCounter % 300 == 0 then
        cleanupCaches()
    end

    if tickCounter % CSF.UPDATE_INTERVAL ~= 0 then return end

    local players = getOnlinePlayers()
    if players:size() < 2 then return end

    local positions = buildPlayerPositions(players)
    syncZombies(positions)
end

local function onInit()
    loadSettings()
    print("[CSF] Custom Sync Fix server loaded - zombie sync only (interval=" .. CSF.UPDATE_INTERVAL .. ", dist=" .. CSF.SYNC_DISTANCE .. ")")
end

Events.OnInitGlobalModData.Add(onInit)
Events.OnTick.Add(onTick)
