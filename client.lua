local isJailed = false
local jailTimerThread = nil

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────

local function TeleportToJail()
    local loc = Config.JailLocation
    local ped  = PlayerPedId()
    DoScreenFadeOut(500)
    Wait(600)
    SetEntityCoords(ped, loc.x, loc.y, loc.z, false, false, false, true)
    SetEntityHeading(ped, loc.h)
    if Config.FreezePlayer then FreezeEntityPosition(ped, true) end
    Wait(500)
    DoScreenFadeIn(500)
end

local function TeleportToRelease()
    local loc = Config.ReleaseLocation
    local ped  = PlayerPedId()
    DoScreenFadeOut(500)
    Wait(600)
    SetEntityCoords(ped, loc.x, loc.y, loc.z, false, false, false, true)
    SetEntityHeading(ped, loc.h)
    FreezeEntityPosition(ped, false)
    Wait(500)
    DoScreenFadeIn(500)
end

-- ─────────────────────────────────────────────
--  HUD countdown timer
-- ─────────────────────────────────────────────

local function StartJailTimer(minutes)
    if jailTimerThread then return end
    local endTime = GetGameTimer() + (minutes * 60 * 1000)

    jailTimerThread = CreateThread(function()
        while isJailed do
            local remaining = endTime - GetGameTimer()
            if remaining <= 0 then break end

            local mins = math.floor(remaining / 60000)
            local secs = math.floor((remaining % 60000) / 1000)

            lib.showTextUI(('🔒 Jail Time: %02d:%02d'):format(mins, secs), {
                position = 'top-center',
                icon     = 'clock',
            })
            Wait(1000)
        end
        lib.hideTextUI()
        jailTimerThread = nil
    end)
end

-- ─────────────────────────────────────────────
--  Escape prevention
-- ─────────────────────────────────────────────

local function StartEscapePrevention()
    CreateThread(function()
        while isJailed do
            local pos     = GetEntityCoords(PlayerPedId())
            local jp      = Config.JailLocation
            if #(pos - vec3(jp.x, jp.y, jp.z)) > Config.JailZone then
                lib.notify({
                    title       = 'Escape Attempt',
                    description = 'You cannot escape jail!',
                    type        = 'error',
                    position    = Config.Notifications.position,
                })
                TeleportToJail()
            end
            Wait(3000)
        end
    end)
end

-- ─────────────────────────────────────────────
--  Jail / Release net event from server
-- ─────────────────────────────────────────────

RegisterNetEvent('jail_script:setJailed', function(jailed, timeMinutes, reason)
    isJailed = jailed

    if jailed then
        TeleportToJail()
        StartJailTimer(timeMinutes)
        StartEscapePrevention()

        Wait(1000)
        lib.notify({
            title       = '🔒 Jailed',
            description = ('Jailed for %d minutes.\nReason: %s'):format(timeMinutes, reason or 'No reason given'),
            type        = 'error',
            position    = Config.Notifications.position,
            duration    = 10000,
        })
    else
        lib.hideTextUI()
        TeleportToRelease()

        --[[lib.notify({
            title       = '✅ Released',
            description = 'You have been released. Your items have been returned.',
            type        = 'success',
            position    = Config.Notifications.position,
            duration    = 8000,
        })--]]
    end
end)

-- ─────────────────────────────────────────────
--  Jail detail dialog (time + reason)
--  Called after officer picks a player from the context menu
-- ─────────────────────────────────────────────

local function OpenJailDialog(targetId, charName)
    local input = lib.inputDialog('🚔 Jail: ' .. charName, {
        {
            type        = 'number',
            label       = 'Jail Time (minutes)',
            description = ('Min %d  —  Max %d'):format(Config.MinJailTime, Config.MaxJailTime),
            required    = true,
            min         = Config.MinJailTime,
            max         = Config.MaxJailTime,
            default     = 10,
        },
        {
            type        = 'input',
            label       = 'Reason',
            description = 'Why is this player being jailed?',
            required    = false,
            default     = 'Criminal activity',
        },
    })

    if not input then return end  -- officer cancelled

    local jailTime = tonumber(input[1]) or Config.MinJailTime
    local reason   = (input[2] ~= '' and input[2]) or 'No reason given'

    TriggerServerEvent('jail_script:jailPlayer', targetId, jailTime, reason)
end

-- ─────────────────────────────────────────────
--  /jail  – open nearby-player picker
-- ─────────────────────────────────────────────

RegisterCommand('jail', function()
    -- Ask server for nearby players & their character names
    local nearby = lib.callback.await('jail_script:getNearbyPlayers', false)

    if not nearby or #nearby == 0 then
        lib.notify({
            title       = 'No Players Nearby',
            description = 'There are no players close enough to jail.',
            type        = 'error',
            position    = Config.Notifications.position,
        })
        return
    end

    -- Build context menu entries — one per nearby player
    local ctxOptions = {}
    for _, p in ipairs(nearby) do
        local pid      = p.id
        local charName = p.charName
        local dist     = p.dist

        ctxOptions[#ctxOptions + 1] = {
            title       = charName,
            description = ('ID: %d  |  %.1f m away'):format(pid, dist),
            icon        = 'handcuffs',
            onSelect    = function()
                OpenJailDialog(pid, charName)
            end,
        }
    end

    lib.registerContext({
        id      = 'jail_select_player',
        title   = '🚔 Select Player to Jail',
        options = ctxOptions,
    })

    lib.showContext('jail_select_player')
end, false)

-- ─────────────────────────────────────────────
--  /unjail – release a jailed player
-- ─────────────────────────────────────────────

RegisterCommand('unjail', function()
    local jailedList = lib.callback.await('jail_script:getJailedPlayers', false)

    if not jailedList or #jailedList == 0 then
        lib.notify({
            title       = 'No Jailed Players',
            description = 'There are currently no players in jail.',
            type        = 'error',
            position    = Config.Notifications.position,
        })
        return
    end

    local ctxOptions = {}
    for _, p in ipairs(jailedList) do
        local pid = p.id
        ctxOptions[#ctxOptions + 1] = {
            title       = p.charName,
            description = ('%d min remaining  |  Reason: %s'):format(p.timeLeft, p.reason),
            icon        = 'door-open',
            onSelect    = function()
                TriggerServerEvent('jail_script:unjailPlayer', pid)
            end,
        }
    end

    lib.registerContext({
        id      = 'jail_unjail_menu',
        title   = '🔓 Release a Prisoner',
        options = ctxOptions,
    })

    lib.showContext('jail_unjail_menu')
end, false)

-- ─────────────────────────────────────────────
--  /jailtime – check own remaining time
-- ─────────────────────────────────────────────

RegisterCommand('jailtime', function()
    TriggerServerEvent('jail_script:checkJailTime')
end, false)

-- ─────────────────────────────────────────────
--  DEV / TESTING ONLY  (remove in production)
--  /jailme [minutes]   – jails yourself so you can
--  test the full flow when playing alone
-- ─────────────────────────────────────────────

RegisterCommand('jailme', function(source, args)
    local minutes = tonumber(args[1]) or 2
    TriggerServerEvent('jail_script:devJailSelf', minutes)
end, false)

-- ─────────────────────────────────────────────
--  Cleanup on resource stop
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(name)
    if GetCurrentResourceName() ~= name then return end
    if isJailed then
        lib.hideTextUI()
    end
end)