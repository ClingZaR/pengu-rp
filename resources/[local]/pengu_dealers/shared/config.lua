-- PenguRP - Illegal Dealers (pengu_dealers) CONFIG.
-- Three illegal NPC types placed by admins around the map. Gangs interact with them to earn
-- personal Criminal XP, gang rep, and DEALER INFLUENCE. Dealer influence is the primary driver
-- of turf expansion (alongside graffiti). ASCII only. luac clean.

Config = {}

Config.dirtyItem    = 'black_money'
Config.interactDist = 2.5

-- Dealer influence is on a 0-100 scale per (dealer, gang). At controlThreshold a gang CONTROLS the
-- dealer (must also be the strict leader) and projects a turf block around it (pengu_turf reads the
-- controlled-dealer list via GetControlledDealers). The dealer menu shows every gang's points out of
-- maxInfluence so crews can see who is winning him over.
Config.controlThreshold = 80       -- >= this (and highest) -> you control the dealer -> you get the block
Config.maxInfluence     = 100      -- per (dealer, gang) influence ceiling (the "/100" shown in-menu)

-- Influence DECAY: control must be MAINTAINED ("keep your dealers happy"). Every influenceDecayMs each
-- gang's influence on every dealer drops by influenceDecay; stop working a dealer and you slide back
-- under controlThreshold and the block releases. A rival dealing with him raises THEIR points, eroding
-- your lead - whoever is highest and >= controlThreshold holds the dealer.
Config.influenceDecay   = 3        -- points lost per dealer per gang each decay tick
Config.influenceDecayMs = 600000   -- decay interval (10 min)

-- =================== dealer types ===================
-- 'accepts' => player sells TO the dealer.
-- 'sells'   => player buys FROM the dealer (doctor only).
Config.dealerTypes = {

    mechanic = {
        label  = 'Chop Mechanic',
        model  = 's_m_y_xmech_01', -- valid LS Customs mechanic ped (s_m_m_mech_01 does NOT exist)
        icon   = 'fa-solid fa-wrench',
        -- CAR PARTS this mechanic buys (exactly what the chop shop yields). Selling anything NOT in this
        -- list is refused. He also shows the current WANTED-CARS list + countdown (from pengu_chopshop).
        accepts = {
            { item = 'chop_engine',    label = 'Engine Block',        price = 1400 },
            { item = 'chop_gearbox',   label = 'Gearbox',             price = 1000 },
            { item = 'chop_catalytic', label = 'Catalytic Converter', price = 1600 },
            { item = 'chop_ecu',       label = 'ECU Unit',            price = 700  },
            { item = 'chop_door',      label = 'Car Door',            price = 450  },
            { item = 'chop_bumper',    label = 'Bumper',              price = 380  },
            { item = 'chop_seat',      label = 'Leather Seat',        price = 320  },
            { item = 'chop_radio',     label = 'Stereo Unit',         price = 360  },
            { item = 'chop_wheel',     label = 'Alloy Wheel',         price = 280  },
            { item = 'chop_battery',   label = 'Car Battery',         price = 220  },
        },
        interactXP = { category = 'criminal', amount = 75 },
        gangRep    = 50,
        influence  = 5,  -- points per sale toward this dealer (0-100 scale; ~16 sales to reach 80)
    },

    drug_dealer = {
        label  = 'Street Dealer',
        model  = 'g_m_y_lost_01',
        icon   = 'fa-solid fa-pills',
        -- processed drugs this dealer buys
        accepts = {
            { item = 'weed_brick', label = 'Weed Brick',  price = 2200 },
            { item = 'coke_brick', label = 'Coke Brick',  price = 8500 },
            { item = 'meth',       label = 'Meth',        price = 1600 },
            { item = 'cokebaggy', label = 'Coke Baggy',  price = 550  },
        },
        interactXP = { category = 'drugs', amount = 100 },
        gangRep    = 75,
        influence  = 6,  -- points per sale (0-100 scale)
    },

    -- Black market doctor: player BUYS from him using dirty money.
    -- All items below exist in ox_inventory items.lua (steroid/adrenaline_shot effects are in
    -- pengu_core/client/consumables.lua).
    doctor = {
        label  = 'Black Market Doctor',
        model  = 's_m_m_doctor_01',
        icon   = 'fa-solid fa-syringe',
        sells  = {
            { item = 'bandage',         label = 'Field Bandage (x5)',      price = 800,   count = 5, minLevel = 1 },
            { item = 'medikit',         label = 'Combat Medkit',           price = 4500,  count = 1, minLevel = 2 }, -- fixed typo: item is 'medikit'
            { item = 'steroid',         label = 'Performance Steroid',     price = 10000, count = 1, minLevel = 3 },
            { item = 'adrenaline_shot', label = 'Adrenaline Shot (burst)', price = 18000, count = 1, minLevel = 4 },
            -- (removed 'armor_kit' - that item does not exist in ox_inventory; body armor is its own dealer now)
        },
        interactXP = { category = 'criminal', amount = 50 },
        gangRep    = 30,
        influence  = 4,  -- points per purchase (0-100 scale)
    },

    -- Arms dealer: gang members ORDER weapons here. The catalog, prices, level-gates and the CRATE-DROP
    -- delivery all live in pengu_blackmarket (OrderWeapon export) - ordering takes dirty money and spawns
    -- a crate you must collect and pry open with a crowbar. No 'accepts'/'sells' list here on purpose.
    weapons = {
        label  = 'Arms Dealer',
        model  = 'g_m_m_armboss_01', -- the ped the old roving black-market dealer used
        icon   = 'fa-solid fa-gun',
        -- NOTE: only dealer INFLUENCE is granted on order (below). Gang rep + criminal XP for a weapon
        -- are granted by pengu_blackmarket when the crate is actually pried open, so they are NOT set here.
        influence  = 5,  -- points per weapon order (0-100 scale)
    },

    -- ARMOR DEALER: body armor only (split out of the all-in-one arms dealer). Sells-type = instant buy
    -- with dirty money, level-gated, like the doctor. Edit the `sells` list freely.
    armor = {
        label  = 'Armor Dealer',
        model  = 's_m_m_armoured_01', -- armored-van guard
        icon   = 'fa-solid fa-shield-halved',
        sells  = {
            { item = 'armour', label = 'Bulletproof Vest',      price = 3000, count = 1, minLevel = 1 },
            { item = 'armour', label = 'Bulletproof Vest (x3)', price = 8000, count = 3, minLevel = 2 },
        },
        interactXP = { category = 'criminal', amount = 40 },
        gangRep    = 25,
        influence  = 4,
    },

    -- GENERAL GOODS / FENCE: cheap criminal tools - crowbar (to pry weapon crates open!), lockpicks,
    -- drills, repair kits. Sells-type; prices kept low (this is the "cheap general items" dealer).
    general = {
        label  = 'Black Market Goods',
        model  = 's_m_y_dealer_01', -- street fence
        icon   = 'fa-solid fa-box-open',
        sells  = {
            { item = 'WEAPON_CROWBAR',   label = 'Crowbar',           price = 600,  count = 1, minLevel = 1 },
            { item = 'lockpick',         label = 'Lockpick',          price = 250,  count = 1, minLevel = 1 },
            { item = 'screwdriverset',   label = 'Screwdriver Set',   price = 400,  count = 1, minLevel = 1 },
            { item = 'repairkit',        label = 'Repair Kit',        price = 800,  count = 1, minLevel = 1 },
            { item = 'advancedlockpick', label = 'Advanced Lockpick', price = 1200, count = 1, minLevel = 2 },
            { item = 'drill',            label = 'Drill',             price = 3000, count = 1, minLevel = 3 },
        },
        interactXP = { category = 'criminal', amount = 35 },
        gangRep    = 20,
        influence  = 4,
    },
}
