require "CustomSyncFix_shared"

local playerTargets = {}

local function loadSettings()
    CSF.PLAYER_INTERP_SPEED = SandboxVars.CustomSyncFix.PlayerInterpSpeed or CSF.PLAYER_INTERP_SPEED
    CSF.DEBUG = SandboxVars.CustomSyncFix.DebugMode or false
end

local function applyPlayerSync(data)
    if not data then return end

    local localPlayer = getPlayer()
    if not localPlayer then return end
    local localId = localPlayer:getOnlineID()
    local px, py = localPlayer:getX(), localPlayer:getY()

    for i = 1, #data do
        local d = data[i]
        if d.id ~= localId then
            if CSF.withinRange(px, py, d.x, d.y) then
                playerTargets[d.id] = d
            end
        end
    end
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
        if z then
            zombieMap[z:getOnlineID()] = z
        end
    end

    local px, py = localPlayer:getX(), localPlayer:getY()
    local toKill = {}

    for i = 1, #data do
        local d = data[i]
        local zombie = zombieMap[d.id]
        if zombie and CSF.withinRange(px, py, d.x, d.y) then
            zombie:setX(d.x)
            zombie:setY(d.y)
            zombie:setZ(d.z)
            zombie:setDirectionAngle(d.dir)
            if d.hp ~= nil then
                zombie:setHealth(d.hp)
            end
            if d.cr ~= nil then
                zombie:setCrawling(d.cr)
            end
            if d.hp and d.hp <= 0 then
                toKill[#toKill + 1] = zombie
            end
        end
    end

    for i = 1, #toKill do
        toKill[i]:setDead(true)
    end
end

local function onServerCommand(module, command, args)
    if module ~= CSF.MOD_ID then return end

    if command == CSF.CMD_SYNC_PLAYERS then
        applyPlayerSync(args)
    elseif command == CSF.CMD_SYNC_ZOMBIES then
        applyZombieSync(args)
    end
end

local function interpolatePlayers()
    local remove = {}

    for id, target in pairs(playerTargets) do
        local player = getPlayerByOnlineID(id)
        if not player then
            remove[#remove + 1] = id
        else
            if target.iv then
                remove[#remove + 1] = id
            else
                local cx, cy, cz = player:getX(), player:getY(), player:getZ()
                local dx = target.x - cx
                local dy = target.y - cy
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist < 0.02 then
                    player:setX(target.x)
                    player:setY(target.y)
                    player:setZ(target.z)
                    if target.dir then
                        player:setDirectionAngle(target.dir)
                    end
                    remove[#remove + 1] = id
                elseif dist > 15.0 then
                    player:setX(target.x)
                    player:setY(target.y)
                    player:setZ(target.z)
                    if target.dir then
                        player:setDirectionAngle(target.dir)
                    end
                    remove[#remove + 1] = id
                else
                    local t = CSF.PLAYER_INTERP_SPEED
                    if dist > 3.0 then
                        t = math.min(t * 2.0, 0.8)
                    end
                    local nx = CSF.lerp(cx, target.x, t)
                    local ny = CSF.lerp(cy, target.y, t)
                    local nz = CSF.lerp(cz, target.z, t)
                    player:setX(nx)
                    player:setY(ny)
                    player:setZ(nz)

                    if target.dir then
                        local curDir = player:getDirectionAngle()
                        local newDir = CSF.lerpAngle(curDir, target.dir, t * 1.5)
                        player:setDirectionAngle(newDir)
                    end
                end
            end
        end
    end

    for i = 1, #remove do
        playerTargets[remove[i]] = nil
    end
end

local function onInit()
    loadSettings()
    print("[CSF] Custom Sync Fix client loaded")
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnInitGlobalModData.Add(onInit)
Events.OnTick.Add(interpolatePlayers)
