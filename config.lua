Config = {}

-- Police job names that are allowed to use this script
Config.PoliceJobs = {
    'lspd',
    'bcso',
    'sahp',
}

-- Jail location (where jailed players are teleported)
Config.JailLocation = {
    x = 1613.12,
    y = 2475.55,
    z = 45.65,
    h = 326.72,
}

-- Release Location (where players are released)
Config.ReleaseLocation = {
    x = 1840.83,
    y = 2585.58,
    z = 45.89,
    h = 262.6,
}

-- Minimum and maximum jail time (in minutes)
Config.MinJailTime = 1
Config.MaxJailTime = 15

-- Notification settings (ox_lib)
Config.Notifications = {
    position = 'top-right',
}

-- Whether to confiscate inventory on jail
Config.ConfiscateInventory = true

-- Whether to freeze player while jailed
Config.FreezePlayer = false

-- How close (in metres) a player must be for the officer to see them in /jail menu
Config.NearbyRange = 10.0

-- How far a player can go from the center of the prison
Config.JailZone = 300
