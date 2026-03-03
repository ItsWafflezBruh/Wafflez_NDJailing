local jailedPlayers = {}
-- jailedPlayers[serverId] = { timeLeft, startTime, charName, reason, officer }

local NDCore = exports["ND_Core"]

local function GetCharacterName(source)
    if NDCore then
        local Player = NDCore:getPlayer(source)
        if Player then
            local firstName = Player.firstname
            local lastName  = Player.lastname
            local full = (firstName .. ' ' .. lastName):gsub('^%s+', ''):gsub('%s+$', '')
            if full ~= '' then return full end
        end
    end

    -- Fallback: Steam/license name
    return GetPlayerName(source) or ('Player %d'):format(source)
end

-- ─────────────────────────────────────────────
--  Police job check
-- ─────────────────────────────────────────────

local function IsPoliceJob(source)
    if NDCore then
        local Player = NDCore:getPlayer(source)
        if Player then
            for _, job in ipairs(Config.PoliceJobs) do
                if Player.job == job then return true end
            end
        end
    end

    return false
end

local function IsJailed(source)
    return jailedPlayers[source] ~= nil
end

-- ─────────────────────────────────────────────
--  lib.callback: nearby players + character names
--  Client sends the server its position; server finds all players within range
-- ─────────────────────────────────────────────

lib.callback.register('jail_script:getNearbyPlayers', function(source)
    if not IsPoliceJob(source) then return {} end

    local officerCoords = GetEntityCoords(GetPlayerPed(source))
    local nearby        = {}

    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid ~= source then
            local ped    = GetPlayerPed(pid)
            local coords = GetEntityCoords(ped)
            local dist   = #(officerCoords - coords)

            if dist <= Config.NearbyRange then
                nearby[#nearby + 1] = {
                    id       = pid,
                    charName = GetCharacterName(pid),
                    dist     = math.floor(dist * 10) / 10,
                }
            end
        end
    end

    -- Sort by distance ascending
    table.sort(nearby, function(a, b) return a.dist < b.dist end)
    return nearby
end)

-- ─────────────────────────────────────────────
--  lib.callback: list of currently jailed players
-- ─────────────────────────────────────────────

lib.callback.register('jail_script:getJailedPlayers', function(source)
    if not IsPoliceJob(source) then return {} end

    local list = {}
    for pid, data in pairs(jailedPlayers) do
        if GetPlayerName(pid) then   -- still online
            local elapsed  = math.floor((os.time() - data.startTime) / 60)
            local timeLeft = math.max(0, data.timeLeft - elapsed)
            list[#list + 1] = {
                id       = pid,
                charName = data.charName,
                timeLeft = timeLeft,
                reason   = data.reason,
            }
        end
    end
    return list
end)

-- ─────────────────────────────────────────────
--  Jail player (triggered from client after dialog)
-- ─────────────────────────────────────────────

RegisterNetEvent('jail_script:jailPlayer', function(targetId, jailTime, reason)
    local source = source

    if not IsPoliceJob(source) then
        lib.notify(source, {
            title       = 'Access Denied',
            description = 'You are not a police officer.',
            type        = 'error',
            position    = Config.Notifications.position,
        })
        return
    end

    targetId = tonumber(targetId)
    jailTime = math.max(Config.MinJailTime, math.min(Config.MaxJailTime, tonumber(jailTime) or Config.MinJailTime))
    reason   = reason or 'No reason given'

    if not GetPlayerName(targetId) then
        lib.notify(source, {
            title       = 'Error',
            description = 'Player not found.',
            type        = 'error',
            position    = Config.Notifications.position,
        })
        return
    end

    if IsJailed(targetId) then
        lib.notify(source, {
            title       = 'Already Jailed',
            description = ('%s is already in jail.'):format(GetCharacterName(targetId)),
            type        = 'warning',
            position    = Config.Notifications.position,
        })
        return
    end

    local targetCharName = GetCharacterName(targetId)

    -- Confiscate inventory
    if Config.ConfiscateInventory then
    	exports.ox_inventory:ConfiscateInventory(targetId)
    end

    -- Record
    jailedPlayers[targetId] = {
        timeLeft  = jailTime,
        startTime = os.time(),
        charName  = targetCharName,
        reason    = reason,
        officer   = GetCharacterName(source),
    }

    -- Notify client
    TriggerClientEvent('jail_script:setJailed', targetId, true, jailTime, reason)

    -- Notify officer
    lib.notify(source, {
        title       = '✅ Player Jailed',
        description = ('Jailed %s for %d minutes.\nReason: %s'):format(targetCharName, jailTime, reason),
        type        = 'success',
        position    = Config.Notifications.position,
    })

    -- Notify target
    lib.notify(targetId, {
        title       = '🔒 You Have Been Jailed',
        description = ('Jailed for %d minutes by %s.\nReason: %s'):format(jailTime, GetCharacterName(source), reason),
        type        = 'error',
        position    = Config.Notifications.position,
        duration    = 10000,
    })

    print(('[Jail] %s jailed %s (%d) for %d min. Reason: %s'):format(
        GetCharacterName(source), targetCharName, targetId, jailTime, reason
    ))

    -- Auto-release timer
    SetTimeout(jailTime * 60 * 1000, function()
        if jailedPlayers[targetId] then
            ReleasePlayer(targetId)
        end
    end)
end)

-- ─────────────────────────────────────────────
--  Unjail (triggered from client context menu)
-- ─────────────────────────────────────────────

RegisterNetEvent('jail_script:unjailPlayer', function(targetId)
    local source = source

    if not IsPoliceJob(source) then
        lib.notify(source, {
            title       = 'Access Denied',
            description = 'You are not a police officer.',
            type        = 'error',
            position    = Config.Notifications.position,
        })
        return
    end

    targetId = tonumber(targetId)

    if not IsJailed(targetId) then
        lib.notify(source, {
            title       = 'Not Jailed',
            description = 'That player is not currently jailed.',
            type        = 'warning',
            position    = Config.Notifications.position,
        })
        return
    end

    local charName = jailedPlayers[targetId].charName
    ReleasePlayer(targetId)

    lib.notify(source, {
        title       = '🔓 Player Released',
        description = ('You released %s from jail.'):format(charName),
        type        = 'success',
        position    = Config.Notifications.position,
    })
end)

-- ─────────────────────────────────────────────
--  Release helper
-- ─────────────────────────────────────────────

function ReleasePlayer(targetId)
    if not jailedPlayers[targetId] then return end

    if Config.ConfiscateInventory then
        exports.ox_inventory:ReturnInventory(targetId)
    end

    local charName = jailedPlayers[targetId].charName
    jailedPlayers[targetId] = nil

    TriggerClientEvent('jail_script:setJailed', targetId, false, 0, nil)

    lib.notify(targetId, {
        title       = '✅ Released from Jail',
        description = 'You have been released. Your items have been returned.',
        type        = 'success',
        position    = Config.Notifications.position,
        duration    = 8000,
    })

    print(('[Jail] %s (%d) has been released.'):format(charName, targetId))
end

-- ─────────────────────────────────────────────
--  Check jail time (called from /jailtime)
-- ─────────────────────────────────────────────

RegisterNetEvent('jail_script:checkJailTime', function()
    local source = source

    if not IsJailed(source) then
        lib.notify(source, {
            title       = 'Not Jailed',
            description = 'You are not currently in jail.',
            type        = 'inform',
            position    = Config.Notifications.position,
        })
        return
    end

    local data    = jailedPlayers[source]
    local elapsed = math.floor((os.time() - data.startTime) / 60)
    local left    = math.max(0, data.timeLeft - elapsed)

    lib.notify(source, {
        title       = '⏱ Jail Time Remaining',
        description = ('%d minute(s) remaining.\nReason: %s'):format(left, data.reason),
        type        = 'inform',
        position    = Config.Notifications.position,
    })
end)

-- ─────────────────────────────────────────────
--  DEV / TESTING ONLY — remove in production
--  Allows a solo dev to jail themselves via /jailme
-- ─────────────────────────────────────────────

RegisterNetEvent('jail_script:devJailSelf', function(minutes)
    local source   = source
    minutes        = math.max(1, math.min(Config.MaxJailTime, tonumber(minutes) or 2))
    local charName = GetCharacterName(source)

    if IsJailed(source) then
        -- Already jailed — release instead so you can toggle
        ReleasePlayer(source)
        return
    end

    -- Confiscate inventory
    if Config.ConfiscateInventory then
    	exports.ox_inventory:ConfiscateInventory(source)
    end

    jailedPlayers[source] = {
        timeLeft  = minutes,
        startTime = os.time(),
        charName  = charName,
        reason    = 'Dev test',
        officer   = 'Console',
    }

    TriggerClientEvent('jail_script:setJailed', source, true, minutes, 'Dev test')

    print(('[Jail][DEV] %s jailed themselves for %d min.'):format(charName, minutes))

    SetTimeout(minutes * 60 * 1000, function()
        if jailedPlayers[source] then
            ReleasePlayer(source)
        end
    end)
end)

-- ─────────────────────────────────────────────
--  Exports for external scripts
-- ─────────────────────────────────────────────

exports('IsJailed', IsJailed)
exports('ReleasePlayer', ReleasePlayer)
