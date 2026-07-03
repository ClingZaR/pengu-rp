return {
    discordWebhook = nil, -- Replace nil with your webhook if you chose to use discord logging over ox_lib logging
    minOnDutyLogTimeMinutes = 30,
    formatDateTime = '%m-%d-%Y %H:%M',

    -- While the config boss menu creation still works, it is recommended to use the runtime export instead.
    -- Single menu: { coords = ..., size = ..., rotation = ..., type = ... }
    -- Multiple menus: { { coords = ..., size = ..., rotation = ..., type = ... }, { ... }  }
    ---@alias GroupName string
    ---@type table<GroupName, ZoneInfo|ZoneInfo[]>
    -- PenguRP: gang boss menus use GTA territory reference points; job menus at
    -- their respective HQ buildings. Coords are approximate — adjust in-game.
    menus = {
        -- ─── Gangs ───────────────────────────────────────────────────────────
        lostmc = {
            {
                coords = vec3(983.69, -90.92, 74.85),
                size = vec3(1.5, 1.5, 1.5),
                rotation = 39.68,
                type = 'gang',
            },
            {
                coords = vec3(976.2, -100.57, 74.87),
                size = vec3(1.5, 1.5, 1.5),
                rotation = 42.76,
                type = 'gang',
            },
        },
        ballas = {
            coords = vec3(108.36, -1649.74, 29.28),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'gang',
        },
        vagos = {
            coords = vec3(351.18, -2054.92, 22.09),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 39.68,
            type = 'gang',
        },
        cartel = {
            coords = vec3(228.32, -2627.19, 5.56),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'gang',
        },
        families = {
            coords = vec3(-312.46, -1547.51, 29.39),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'gang',
        },
        triads = {
            coords = vec3(689.0, -924.48, 24.29),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'gang',
        },

        -- ─── Jobs ────────────────────────────────────────────────────────────
        police = {
            coords = vec3(441.68, -982.23, 30.69),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'job',
        },
        bcso = {
            coords = vec3(1853.28, 3686.52, 34.27),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'job',
        },
        ambulance = {
            coords = vec3(306.78, -599.56, 43.28),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'job',
        },
        mechanic = {
            coords = vec3(-338.31, -130.59, 38.21),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'job',
        },
        taxi = {
            coords = vec3(901.16, -180.32, 73.21),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'job',
        },
        trucker = {
            coords = vec3(99.44, -3174.99, 5.87),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            type = 'job',
        },
    },
}
