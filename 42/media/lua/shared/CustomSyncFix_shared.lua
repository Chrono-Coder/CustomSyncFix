CSF = {}

CSF.MOD_ID = "CustomSyncFix"

CSF.UPDATE_INTERVAL = 30
CSF.SYNC_DISTANCE = 100
CSF.PLAYER_INTERP_SPEED = 0.35
CSF.VEHICLE_INTERP_SPEED = 0.4
CSF.SYNC_ZOMBIES = true
CSF.MAX_ZOMBIES = 150
CSF.DEBUG = false

CSF.PLAYER_DELTA_EPSILON = 0.05
CSF.VEHICLE_DELTA_EPSILON = 0.1
CSF.ZOMBIE_DELTA_EPSILON = 0.1

CSF.CMD_SYNC_PLAYERS = "sp"
CSF.CMD_SYNC_VEHICLES = "sv"
CSF.CMD_SYNC_ZOMBIES = "sz"

function CSF.distSq(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

function CSF.withinRange(x1, y1, x2, y2)
    return CSF.distSq(x1, y1, x2, y2) <= CSF.SYNC_DISTANCE * CSF.SYNC_DISTANCE
end

function CSF.lerpAngle(from, to, t)
    local delta = to - from
    while delta > 180 do delta = delta - 360 end
    while delta < -180 do delta = delta + 360 end
    return from + delta * t
end

function CSF.lerp(a, b, t)
    return a + (b - a) * t
end
