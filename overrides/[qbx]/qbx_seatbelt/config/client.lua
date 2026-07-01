return {
    keybind = 'B', -- Keybind to toggle seatbelt (https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/)
    -- PenguRP: speeds below are in MPH to match the pengu_hud speedometer default unit.
    -- Sounds are baked into audiodirectory/ and are not configurable here.
    useMPH = true, -- Use MPH instead of KMH
    minSpeedUnbuckled = 30.0, -- Minimum speed to fly through windscreen when seatbelt is off
    minSpeedBuckled = 100.0, -- Minimum speed to fly through windscreen when seatbelt is on
    harness = {
        disableFlyingThroughWindscreen = true, -- Disable flying through windscreen when harness is on
        minSpeed = 125.0 -- If the above is set to false, minimum speed to fly through windscreen when harness is on
    }
}
