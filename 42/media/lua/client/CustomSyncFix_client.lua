require "CustomSyncFix_shared"

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

    if command == CSF.CMD_SYNC_ZOMBIES then
        applyZombieSync(args)
    end
end

local function onInit()
    loadSettings()
    print("[CSF] Custom Sync Fix client loaded")
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnInitGlobalModData.Add(onInit)
