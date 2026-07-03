return {
    -- PenguRP: cola + medikit were referenced by data/shops.lua (General/Liquor/Medicine) but had no
    -- item definition -> ox_inventory logged "no item" warnings + the entries were unbuyable. cola is a
    -- working thirst drink (effect via client.status, like sprunk/water). medikit stays label+weight
    -- only on purpose: its use logic lives in qbx_ambulancejob (CreateUseableItem 'medikit' ->
    -- hospital:server:UseMedikit), so do NOT add a client block here.
    ['cola'] = {
        label = 'eCola',
        weight = 350,
        client = {
            status = { thirst = 200000 },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            usetime = 2500,
        },
    },
    ['medikit'] = {
        label = 'Medikit',
        weight = 2500,
    },
    ['testburger'] = {
        label = 'Test Burger',
        weight = 220,
        degrade = 60,
        client = {
            image = 'burger_chicken.png',
            status = { hunger = 200000 },
            anim = 'eating',
            prop = 'burger',
            usetime = 2500,
            export = 'ox_inventory_examples.testburger'
        },
        server = {
            export = 'ox_inventory_examples.testburger',
            test = 'what an amazingly delicious burger, amirite?'
        },
        buttons = {
            {
                label = 'Lick it',
                action = function(slot)
                    print('You licked the burger')
                end
            },
            {
                label = 'Squeeze it',
                action = function(slot)
                    print('You squeezed the burger :(')
                end
            },
            {
                label = 'What do you call a vegan burger?',
                group = 'Hamburger Puns',
                action = function(slot)
                    print('A misteak.')
                end
            },
            {
                label = 'What do frogs like to eat with their hamburgers?',
                group = 'Hamburger Puns',
                action = function(slot)
                    print('French flies.')
                end
            },
            {
                label = 'Why were the burger and fries running?',
                group = 'Hamburger Puns',
                action = function(slot)
                    print('Because they\'re fast food.')
                end
            }
        },
        consume = 0.3
    },

    ['bandage'] = {
        label = 'Bandage',
        weight = 115,
    },

    ['burger'] = {
        label = 'Burger',
        weight = 220,
        client = {
            status = { hunger = 200000 },
            anim = 'eating',
            prop = 'burger',
            usetime = 2500,
            notification = 'You ate a delicious burger'
        },
    },

    ['sprunk'] = {
        label = 'Sprunk',
        weight = 350,
        client = {
            status = { thirst = 200000 },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            prop = { model = `prop_ld_can_01`, pos = vec3(0.01, 0.01, 0.06), rot = vec3(5.0, 5.0, -180.5) },
            usetime = 2500,
            notification = 'You quenched your thirst with a sprunk'
        }
    },

    ['parachute'] = {
        label = 'Parachute',
        weight = 8000,
        stack = false,
        client = {
            anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d' },
            usetime = 1500
        }
    },

    ['garbage'] = {
        label = 'Garbage',
    },

    ['paperbag'] = {
        label = 'Paper Bag',
        weight = 1,
        stack = false,
        close = false,
        consume = 0
    },

    ['panties'] = {
        label = 'Knickers',
        weight = 10,
        consume = 0,
        client = {
            status = { thirst = -100000, stress = -25000 },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            prop = { model = `prop_cs_panties_02`, pos = vec3(0.03, 0.0, 0.02), rot = vec3(0.0, -13.5, -1.5) },
            usetime = 2500,
        }
    },

    ['lockpick'] = {
        label = 'Lockpick',
        weight = 160,
    },

    ['phone'] = {
        label = 'Phone',
        weight = 190,
        stack = false,
        consume = 0,
        client = {
            add = function(total)
                if total > 0 then
                    pcall(function() return exports.npwd:setPhoneDisabled(false) end)
                end
            end,

            remove = function(total)
                if total < 1 then
                    pcall(function() return exports.npwd:setPhoneDisabled(true) end)
                end
            end
        }
    },

    ['mustard'] = {
        label = 'Mustard',
        weight = 500,
        client = {
            status = { hunger = 25000, thirst = 25000 },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            prop = { model = `prop_food_mustard`, pos = vec3(0.01, 0.0, -0.07), rot = vec3(1.0, 1.0, -1.5) },
            usetime = 2500,
            notification = 'You... drank mustard'
        }
    },

    ['water'] = {
        label = 'Water',
        weight = 500,
        client = {
            status = { thirst = 200000 },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            prop = { model = `prop_ld_flow_bottle`, pos = vec3(0.03, 0.03, 0.02), rot = vec3(0.0, 0.0, -1.5) },
            usetime = 2500,
            cancel = true,
            notification = 'You drank some refreshing water'
        }
    },

    ['armour'] = {
        label = 'Bulletproof Vest',
        weight = 3000,
        stack = false,
        client = {
            anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d' },
            usetime = 3500
        }
    },

    ['clothing'] = {
        label = 'Clothing',
        consume = 0,
    },

    ['money'] = {
        label = 'Money',
    },

    ['black_money'] = {
        label = 'Dirty Money',
    },

    ['id_card'] = {
        label = 'Identification Card',
    },

    ['driver_license'] = {
        label = 'Drivers License',
    },

    ['weaponlicense'] = {
        label = 'Weapon License',
    },

    ['lawyerpass'] = {
        label = 'Lawyer Pass',
    },

    ['radio'] = {
        label = 'Radio',
        weight = 1000,
        allowArmed = true,
        consume = 0,
        client = {
            event = 'mm_radio:client:use'
        }
    },

    ['jammer'] = {
        label = 'Radio Jammer',
        weight = 10000,
        allowArmed = true,
        client = {
            event = 'mm_radio:client:usejammer'
        }
    },

    ['radiocell'] = {
        label = 'AAA Cells',
        weight = 1000,
        stack = true,
        allowArmed = true,
        client = {
            event = 'mm_radio:client:recharge'
        }
    },

    ['advancedlockpick'] = {
        label = 'Advanced Lockpick',
        weight = 500,
    },

    ['screwdriverset'] = {
        label = 'Screwdriver Set',
        weight = 500,
    },

    ['electronickit'] = {
        label = 'Electronic Kit',
        weight = 500,
    },

    ['cleaningkit'] = {
        label = 'Cleaning Kit',
        weight = 500,
    },

    ['repairkit'] = {
        label = 'Repair Kit',
        weight = 2500,
    },

    ['advancedrepairkit'] = {
        label = 'Advanced Repair Kit',
        weight = 4000,
    },

    ['diamond_ring'] = {
        label = 'Diamond',
        weight = 1500,
    },

    ['rolex'] = {
        label = 'Golden Watch',
        weight = 1500,
    },

    ['goldbar'] = {
        label = 'Gold Bar',
        weight = 1500,
    },

    ['goldchain'] = {
        label = 'Golden Chain',
        weight = 1500,
    },

    ['crack_baggy'] = {
        label = 'Crack Baggy',
        weight = 100,
    },

    ['cokebaggy'] = {
        label = 'Bag of Coke',
        weight = 100,
    },

    ['coke_brick'] = {
        label = 'Coke Brick',
        weight = 2000,
    },

    ['coke_small_brick'] = {
        label = 'Coke Package',
        weight = 1000,
    },

    ['xtcbaggy'] = {
        label = 'Bag of Ecstasy',
        weight = 100,
    },

    ['meth'] = {
        label = 'Methamphetamine',
        weight = 100,
    },

    ['oxy'] = {
        label = 'Oxycodone',
        weight = 100,
    },

    ['weed_ak47'] = {
        label = 'AK47 2g',
        weight = 200,
    },

    ['weed_ak47_seed'] = {
        label = 'AK47 Seed',
        weight = 1,
        consume = 0, -- PenguRP: qbx_weed removeSeed handles consumption on a successful plant
        client = { export = 'pengu_drugs.plantSeed' },
    },

    ['weed_skunk'] = {
        label = 'Skunk 2g',
        weight = 200,
    },

    ['weed_skunk_seed'] = {
        label = 'Skunk Seed',
        weight = 1,
        consume = 0, -- PenguRP: qbx_weed removeSeed handles consumption on a successful plant
        client = { export = 'pengu_drugs.plantSeed' },
    },

    ['weed_amnesia'] = {
        label = 'Amnesia 2g',
        weight = 200,
    },

    ['weed_amnesia_seed'] = {
        label = 'Amnesia Seed',
        weight = 1,
        consume = 0, -- PenguRP: qbx_weed removeSeed handles consumption on a successful plant
        client = { export = 'pengu_drugs.plantSeed' },
    },

    ['weed_og-kush'] = {
        label = 'OGKush 2g',
        weight = 200,
    },

    ['weed_og-kush_seed'] = {
        label = 'OGKush Seed',
        weight = 1,
        consume = 0, -- PenguRP: qbx_weed removeSeed handles consumption on a successful plant
        client = { export = 'pengu_drugs.plantSeed' },
    },

    ['weed_white-widow'] = {
        label = 'White Widow 2g', -- PenguRP: was mislabeled 'OGKush 2g' (copy-paste bug)
        weight = 200,
    },

    ['weed_white-widow_seed'] = {
        label = 'White Widow Seed',
        weight = 1,
        consume = 0, -- PenguRP: qbx_weed removeSeed handles consumption on a successful plant
        client = { export = 'pengu_drugs.plantSeed' },
    },

    ['weed_purple-haze'] = {
        label = 'Purple Haze 2g',
        weight = 200,
    },

    ['weed_purple-haze_seed'] = {
        label = 'Purple Haze Seed',
        weight = 1,
        consume = 0, -- PenguRP: qbx_weed removeSeed handles consumption on a successful plant
        client = { export = 'pengu_drugs.plantSeed' },
    },

    ['weed_brick'] = {
        label = 'Weed Brick',
        weight = 2000,
    },

    ['weed_nutrition'] = {
        label = 'Plant Fertilizer',
        weight = 2000,
        client = { export = 'pengu_drugs.feedPlant' }, -- PenguRP: wire qbx_weed feeding (consume = 1 default)
    },

    ['joint'] = {
        label = 'Joint',
        weight = 200,
    },

    ['rolling_paper'] = {
        label = 'Rolling Paper',
        weight = 0,
    },

    ['empty_weed_bag'] = {
        label = 'Empty Weed Bag',
        weight = 0,
    },

    ['firstaid'] = {
        label = 'First Aid',
        weight = 2500,
    },

    ['ifaks'] = {
        label = 'Individual First Aid Kit',
        weight = 2500,
    },

    ['painkillers'] = {
        label = 'Painkillers',
        weight = 400,
    },

    ['firework1'] = {
        label = '2Brothers',
        weight = 1000,
    },

    ['firework2'] = {
        label = 'Poppelers',
        weight = 1000,
    },

    ['firework3'] = {
        label = 'WipeOut',
        weight = 1000,
    },

    ['firework4'] = {
        label = 'Weeping Willow',
        weight = 1000,
    },

    ['steel'] = {
        label = 'Steel',
        weight = 100,
    },

    ['rubber'] = {
        label = 'Rubber',
        weight = 100,
    },

    ['metalscrap'] = {
        label = 'Metal Scrap',
        weight = 100,
    },

    ['iron'] = {
        label = 'Iron',
        weight = 100,
    },

    ['copper'] = {
        label = 'Copper',
        weight = 100,
    },

    ['aluminum'] = {
        label = 'Aluminium',
        weight = 100,
    },

    ['plastic'] = {
        label = 'Plastic',
        weight = 100,
    },

    ['glass'] = {
        label = 'Glass',
        weight = 100,
    },

    ['gatecrack'] = {
        label = 'Gatecrack',
        weight = 1000,
    },

    ['cryptostick'] = {
        label = 'Crypto Stick',
        weight = 100,
    },

    ['trojan_usb'] = {
        label = 'Trojan USB',
        weight = 100,
    },

    ['toaster'] = {
        label = 'Toaster',
        weight = 5000,
    },

    ['small_tv'] = {
        label = 'Small TV',
        weight = 100,
    },

    ['security_card_01'] = {
        label = 'Security Card A',
        weight = 100,
    },

    ['security_card_02'] = {
        label = 'Security Card B',
        weight = 100,
    },

    ['drill'] = {
        label = 'Drill',
        weight = 5000,
    },

    ['thermite'] = {
        label = 'Thermite',
        weight = 1000,
    },

    ['diving_gear'] = {
        label = 'Diving Gear',
        weight = 30000,
    },

    ['diving_fill'] = {
        label = 'Diving Tube',
        weight = 3000,
    },

    ['antipatharia_coral'] = {
        label = 'Antipatharia',
        weight = 1000,
    },

    ['dendrogyra_coral'] = {
        label = 'Dendrogyra',
        weight = 1000,
    },

    ['jerry_can'] = {
        label = 'Jerrycan',
        weight = 3000,
    },

    ['nitrous'] = {
        label = 'Nitrous',
        weight = 1000,
    },

    ['wine'] = {
        label = 'Wine',
        weight = 500,
    },

    ['grape'] = {
        label = 'Grape',
        weight = 10,
    },

    ['grapejuice'] = {
        label = 'Grape Juice',
        weight = 200,
    },

    ['coffee'] = {
        label = 'Coffee',
        weight = 200,
    },

    ['vodka'] = {
        label = 'Vodka',
        weight = 500,
    },

    ['whiskey'] = {
        label = 'Whiskey',
        weight = 200,
    },

    ['beer'] = {
        label = 'Beer',
        weight = 200,
    },

    ['sandwich'] = {
        label = 'Sandwich',
        weight = 200,
    },

    ['walking_stick'] = {
        label = 'Walking Stick',
        weight = 1000,
    },

    ['lighter'] = {
        label = 'Lighter',
        weight = 200,
    },

    ['binoculars'] = {
        label = 'Binoculars',
        weight = 800,
    },

    ['stickynote'] = {
        label = 'Sticky Note',
        weight = 0,
    },

    ['empty_evidence_bag'] = {
        label = 'Empty Evidence Bag',
        weight = 200,
    },

    ['filled_evidence_bag'] = {
        label = 'Filled Evidence Bag',
        weight = 200,
    },

    ['harness'] = {
        label = 'Harness',
        weight = 200,
    },

    ['handcuffs'] = {
        label = 'Handcuffs',
        weight = 200,
    },

    -- noob-evidences items
    ['evidence_laptop'] = {
        label = 'Evidence Laptop',
        weight = 2000,
    },
    ['evidence_box'] = {
        label = 'Evidence Box',
        weight = 500,
        stack = false,
        container = {
            slots = 20,
            maxWeight = 5000,
        },
    },
    ['forensic_kit'] = {
        label = 'Forensic Kit',
        weight = 300,
        degrade = 60 * 24,
    },
    ['collected_blood'] = {
        label = 'Blood Sample',
        weight = 50,
        stack = false,
    },
    ['collected_saliva'] = {
        label = 'Saliva Sample',
        weight = 50,
        stack = false,
    },
    ['collected_magazine'] = {
        label = 'Collected Magazine',
        weight = 100,
        stack = false,
    },
    ['collected_fingerprint'] = {
        label = 'Fingerprint Sample',
        weight = 50,
        stack = false,
    },
    ['hydrogen_peroxide'] = {
        label = 'Hydrogen Peroxide',
        weight = 300,
    },
    ['fingerprint_scanner'] = {
        label = 'Fingerprint Scanner',
        weight = 400,
    },
    ['spy_microphone'] = {
        label = 'Spy Microphone',
        weight = 100,
        stack = false,
    },
    -- PenguRP Traffic & Pursuit (pengu_traffic). Reusable police tools (consume = 0).
    -- (Radar is no longer an item; it is a vehicle-mounted HUD in police cars.)
    ['spikestrip'] = {
        label = 'Spike Strip',
        description = 'Deploy across the road to burst the tires of speeding vehicles.',
        weight = 8000,
        stack = true,
        close = true,
        consume = 0,
        client = { export = 'pengu_traffic.spikestrip' },
    },
    ['trafficcone'] = {
        label = 'Traffic Cone',
        description = 'Place to mark off a scene or lane.',
        weight = 1500,
        stack = true,
        close = true,
        consume = 0,
        client = { export = 'pengu_traffic.trafficcone' },
    },
    -- PenguRP Drug Supply Chain (pengu_drugs - Phase 3.2). Raw + intermediate COCAINE items; the
    -- finished cokebaggy/coke_brick already exist above. Images reuse the stock cocaine art. These
    -- are ADDITIVE (do not touch existing items). Re-apply if ox_inventory is updated/overwritten.
    ['coca_leaf'] = {
        label = 'Coca Leaf',
        description = 'Raw coca leaves harvested from a field. Wash them into paste at a cocaine lab.',
        weight = 50,
        stack = true,
        close = false,
        image = 'cocaineleaf.png',
    },
    ['coca_paste'] = {
        label = 'Coca Paste',
        description = 'Washed coca paste. Cut and bag it into sellable product at a cocaine lab.',
        weight = 200,
        stack = true,
        close = false,
        image = 'cocaine.png',
    },
    -- PenguRP METH chain precursors (the finished 'meth' item already exists above + is corner-sellable).
    ['pseudo'] = {
        label = 'Pseudoephedrine',
        description = 'Cold-medicine precursor. Cook it down at a meth lab.',
        weight = 100,
        stack = true,
        close = false,
        image = 'meth_baggy.png',
    },
    ['meth_batch'] = {
        label = 'Meth Batch',
        description = 'A raw, uncrystallized batch. Finish it into product at a meth lab.',
        weight = 300,
        stack = true,
        close = false,
        image = 'meth_tray.png',
    },
    -- PenguRP Civilian Gathering Jobs (pengu_jobs - Phase 4.1). Legal gather goods. Additive.
    ['raw_fish'] = {
        label = 'Fish',
        description = 'A fresh catch. Sell it at the fish market.',
        weight = 200,
        stack = true,
        close = false,
        image = 'fish.png',
    },
    ['wood'] = {
        label = 'Wood',
        description = 'Felled timber. Sell it at the lumber yard.',
        weight = 500,
        stack = true,
        close = false,
    },
    ['cooked_fish'] = {
        label = 'Cooked Fish',
        description = 'Grilled fillet. Worth more than a raw catch.',
        weight = 180,
        stack = true,
        close = false,
        image = 'fish.png',
    },
    ['plank'] = {
        label = 'Plank',
        description = 'Milled lumber. Worth more than raw wood.',
        weight = 300,
        stack = true,
        close = false,
    },
    -- PenguRP job TOOLS (pengu_jobs - Phase 4.1 tool-gating). Durable (not consumed); buy at a hardware store.
    ['pickaxe'] = {
        label = 'Pickaxe',
        description = 'Required to mine ore.',
        weight = 2000,
        stack = false,
        close = false,
        image = 'drill.png',
    },
    ['axe'] = {
        label = 'Axe',
        description = 'Required to chop wood.',
        weight = 2000,
        stack = false,
        close = false,
        image = 'WEAPON_BATTLEAXE.png',
    },
    -- PenguRP fishing items (qw_fishing)
    ['catfish']       = { label = 'Catfish',         weight = 500, stack = true, description = 'A catfish. Sell at the fish market.' },
    ['largemouthbass']= { label = 'Largemouth Bass', weight = 600, stack = true, description = 'A largemouth bass.' },
    ['redfish']       = { label = 'Redfish',         weight = 550, stack = true, description = 'A redfish.' },
    ['salmon']        = { label = 'Salmon',          weight = 700, stack = true, description = 'A salmon.' },
    ['stingray']      = { label = 'Stingray',        weight = 900, stack = true, description = 'A stingray. Rare catch.' },
    ['stripedbass']   = { label = 'Striped Bass',    weight = 650, stack = true, description = 'A striped bass.' },
    ['whale']         = { label = 'Whale (Toy)',     weight = 200, stack = true, description = 'A tiny toy whale. Very rare catch.' },
    ['fishbait']      = { label = 'Fish Bait',       weight = 50,  stack = true, description = 'Bait for fishing.' },
    ['bucket']        = { label = 'Bait Bucket',     weight = 300, stack = false, description = 'A bucket of bait. Use near water to fish.' },

    ['fishingrod'] = {
        label = 'Fishing Rod',
        description = 'Required to fish.',
        weight = 1500,
        stack = false,
        close = false,
        image = 'fishingrod.png',
    },
    -- PenguRP Farming & Hunting (pengu_jobs Phase 4.2). Raw goods + tools. Additive.
    ['farm_seed']     = { label = 'Farm Seeds',     description = 'Assorted vegetable seeds. Use at a farm field.', weight = 100, stack = true,  close = true,  consume = 0 },
    ['corn']          = { label = 'Corn',           description = 'Fresh harvested corn.',                          weight = 200, stack = true,  close = true },
    ['potato']        = { label = 'Potato',         description = 'Fresh potato.',                                  weight = 300, stack = true,  close = true },
    ['carrot']        = { label = 'Carrot',         description = 'Fresh carrot.',                                  weight = 150, stack = true,  close = true },
    -- PenguRP carcass items (mana_hunting). Grade stored in metadata.type; image in metadata.image.
    ['carcass_boar']      = { label = 'Boar Carcass',     weight = 3000, stack = false, description = 'A harvested boar. Sell at the slaughter pen.' },
    ['carcass_hawk']      = { label = 'Hawk Carcass',     weight = 500,  stack = false, description = 'A harvested chicken hawk.' },
    ['carcass_cormorant'] = { label = 'Cormorant Carcass',weight = 400,  stack = false, description = 'A harvested cormorant.' },
    ['carcass_coyote']    = { label = 'Coyote Carcass',   weight = 1200, stack = false, description = 'A harvested coyote.' },
    ['carcass_deer']      = { label = 'Deer Carcass',     weight = 5000, stack = false, description = 'A harvested deer. Drag to your vehicle.' },
    ['carcass_mtlion']    = { label = 'Mountain Lion Carcass', weight = 4000, stack = false, description = 'A harvested mountain lion.' },
    ['carcass_rabbit']    = { label = 'Rabbit Carcass',   weight = 600,  stack = false, description = 'A harvested rabbit.' },
    ['raw_venison']   = { label = 'Raw Venison',    description = 'Fresh venison. Butcher for better value.',       weight = 600, stack = true,  close = true },
    ['venison_steak'] = { label = 'Venison Steak',  description = 'Butchered venison. Premium price at market.',   weight = 400, stack = true,  close = true },
    ['rabbit_fur']    = { label = 'Rabbit Fur',     description = 'Soft pelt. Tan with others into leather.',      weight = 200, stack = true,  close = true },
    ['leather']       = { label = 'Leather',        description = 'Tanned leather. High market value.',            weight = 300, stack = true,  close = true },
    ['hunting_knife']    = { label = 'Hunting Knife',   description = 'Required to hunt and field-dress animals.',       weight = 400, stack = false, close = false, consume = 0 },
    ['vegetable_soup']   = { label = 'Vegetable Soup',  description = 'Hearty soup from farm produce. Restores hunger and thirst.', weight = 250, stack = true,  close = true },
    ['water_bottle']     = { label = 'Water Bottle',    description = 'Clean drinking water. Restores thirst.',          weight = 100, stack = true,  close = true },
    -- PenguRP Delivery Courier (pengu_jobs depot routes). Route-bound parcel: handed out when a
    -- route starts, one removed per delivered stop, leftovers removed when the route closes. No other use.
    ['package'] = {
        label = 'Package',
        description = 'A sealed courier parcel. Deliver it to the marked stop.',
        weight = 500,
        stack = true,
        close = true,
        image = 'evidence_box.png',
    },
    -- PenguRP gang GRAFFITI (pengu_turf Phase 3). Used in contestable turf to tag a wall, which builds
    -- your gang's influence. Not auto-consumed (consume = 0); pengu_turf removes one server-side only on a
    -- successful tag. client.export calls pengu_turf:useSpraycan on use.
    ['spraycan'] = {
        label = 'Spray Can',
        description = 'Tag a wall in contestable turf to grow your gang influence.',
        weight = 500,
        stack = true,
        close = true,
        consume = 0,
        client = {
            export = 'pengu_turf.useSpraycan',
        },
    },

    -- PenguRP chop-shop car parts (stripped from WANTED cars at a chop point; sold to a mechanic dealer).
    -- No item images yet -> blank inventory icons (cosmetic). Add chop_*.png to web/images later.
    ['chop_engine']    = { label = 'Engine Block',         weight = 8000, stack = true, description = 'Stripped engine block. A chop mechanic pays well for these.' },
    ['chop_gearbox']   = { label = 'Gearbox',              weight = 4000, stack = true, description = 'Stripped gearbox.' },
    ['chop_ecu']       = { label = 'ECU Unit',             weight = 600,  stack = true, description = 'Vehicle electronic control unit.' },
    ['chop_door']      = { label = 'Car Door',             weight = 5000, stack = true, description = 'Stripped car door.' },
    ['chop_wheel']     = { label = 'Alloy Wheel',          weight = 2500, stack = true, description = 'Alloy wheel and tyre.' },
    ['chop_bumper']    = { label = 'Bumper',               weight = 3000, stack = true, description = 'Stripped bumper assembly.' },
    ['chop_catalytic'] = { label = 'Catalytic Converter',  weight = 1500, stack = true, description = 'Precious-metal catalytic converter.' },
    ['chop_battery']   = { label = 'Car Battery',          weight = 2000, stack = true, description = 'Vehicle battery.' },
    ['chop_radio']     = { label = 'Stereo Unit',          weight = 1200, stack = true, description = 'Head unit / stereo.' },
    ['chop_seat']      = { label = 'Leather Seat',         weight = 3500, stack = true, description = 'Stripped leather seat.' },

    -- PenguRP gun parts (pengu_gunrunning). Gang members scavenge these from placed part spots;
    -- crafted into weapons at tiered gang workbenches. Images reuse metalscrap/steel icons.
    ['gun_barrel']  = { label = 'Gun Barrel',   weight = 500,  stack = true,  description = 'A machined rifle or pistol barrel.' },
    ['gun_slide']   = { label = 'Gun Slide',    weight = 300,  stack = true,  description = 'Pistol slide assembly.' },
    ['gun_frame']   = { label = 'Gun Frame',    weight = 800,  stack = true,  description = 'Polymer or metal firearm frame.' },
    ['gun_spring']  = { label = 'Recoil Spring',weight = 100,  stack = true,  description = 'Compressed spring and rod assembly.' },
    ['gun_trigger'] = { label = 'Trigger Group',weight = 150,  stack = true,  description = 'Trigger, sear, and housing.' },
    ['gun_stock']   = { label = 'Rifle Stock',  weight = 600,  stack = true,  description = 'Folding or fixed rifle stock.' },

    -- PenguRP doctor-dealer consumables + RP papers. steroid/adrenaline_shot are sold by the
    -- pengu_dealers Black Market Doctor; effects live in pengu_core/client/consumables.lua
    -- (the export calls exports.ox_inventory:useItem itself, which consumes the item and runs
    -- the anim/usetime progress bar). Images reuse stock art (no dedicated pngs yet).
    ['steroid'] = {
        label = 'Performance Steroid',
        description = 'Fully restores stamina and boosts sprint speed for two minutes.',
        weight = 200,
        stack = true,
        close = true,
        image = 'painkillers.png',
        client = {
            export = 'pengu_core.useSteroid',
            anim = { dict = 'mp_suicide', clip = 'pill' },
            usetime = 2500,
        },
    },
    ['adrenaline_shot'] = {
        label = 'Adrenaline Shot',
        description = 'Instantly restores health and calms the nerves.',
        weight = 150,
        stack = true,
        close = true,
        image = 'ifaks.png',
        client = {
            export = 'pengu_core.useAdrenaline',
            anim = { dict = 'mp_suicide', clip = 'pill' },
            usetime = 1500,
        },
    },
    ['wallet'] = {
        label = 'Wallet',
        description = 'A worn leather wallet.',
        weight = 100,
        consume = 0, -- RP prop; never destroyed on use
    },
    ['business_license'] = {
        label = 'Business License',
        description = 'State-issued license to operate a business.',
        weight = 0,
        image = 'weaponlicense.png',
        consume = 0, -- document; never destroyed on use
    },

    -- PenguRP: keep-companion-ox pet system (resources/[standalone]/keep-companion-ox).
    -- PenguRP: item names must match Config.pets / Config.core_items in that resource.
    -- PenguRP: pets are unique (stack = false) because pet state lives in item metadata.
    ['keepcompanionhusky'] = {
        label = 'Husky',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Also the nickname everyone calls you behind your back.',
    },
    ['keepcompanionpoodle'] = {
        label = 'Poodle',
        weight = 5000,
        stack = false,
        close = true,
        description = 'This dog haircut is more expensive than your car.',
    },
    ['keepcompanionrottweiler'] = {
        label = 'Rottweiler',
        weight = 5000,
        stack = false,
        close = true,
        description = 'A butchers best friend.',
    },
    ['keepcompanionwesty'] = {
        label = 'Westie',
        weight = 5000,
        stack = false,
        close = true,
        description = 'A great breed for hunting rats, and wearing cute sweaters.',
    },
    ['keepcompanioncat'] = {
        label = 'Cat',
        weight = 5000,
        stack = false,
        close = true,
        description = 'What is new, pussycat?',
    },
    ['keepcompanionpug'] = {
        label = 'Pug',
        weight = 5000,
        stack = false,
        close = true,
        description = 'The snorting haunts you in your sleep.',
    },
    ['keepcompanionretriever'] = {
        label = 'Retriever',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Americas favorite dog.',
    },
    ['keepcompanionshepherd'] = {
        label = 'Border Collie',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Useful to herd your flock of sheep.',
    },
    ['keepcompanionrabbit'] = {
        label = 'Rabbit',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Boing boing boing boing.',
    },
    ['keepcompanionhen'] = {
        label = 'Hen',
        weight = 5000,
        stack = false,
        close = true,
        description = 'A best friend AND lunch. Two for one!',
    },
    ['keepcompanionrat'] = {
        label = 'Rat',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Snitches get stitches, but rats get scritches.',
    },
    ['keepcompanionmtlion'] = {
        label = 'Mountain Lion',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Definitely legal. Definitely.',
    },
    ['keepcompanionmtlion2'] = {
        label = 'Panther',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Sleek, silent, and extremely illegal.',
    },
    ['keepcompanioncoyote'] = {
        label = 'Coyote',
        weight = 5000,
        stack = false,
        close = true,
        description = 'Do not feed after midnight. Or ever, really.',
    },
    ['keepcompanionk9unit'] = {
        label = 'K9 Unit Malinois',
        weight = 5000,
        stack = false,
        close = true,
        description = 'LSPD exclusive K9.',
    },
    ['petfood'] = {
        label = 'Pet Food',
        weight = 500,
        stack = true,
        close = true,
        description = 'Nom nom for your pom pom.',
    },
    ['collarpet'] = {
        label = 'Pet Collar',
        weight = 500,
        stack = false,
        close = true,
        description = 'Transfer ownership of your pet.',
    },
    ['firstaidforpet'] = {
        label = 'Pet First-aid Kit',
        weight = 500,
        stack = true,
        close = true,
        description = 'Bring your pet back from the dead again and again.',
    },
    ['petnametag'] = {
        label = 'Pet Name Tag',
        weight = 500,
        stack = true,
        close = true,
        description = 'Rename your pet.',
    },
    ['petwaterbottleportable'] = {
        label = 'Pet Water Bottle',
        weight = 500,
        stack = false,
        close = true,
        description = 'Water for your pet. Stop trying to drink this.',
    },
    ['petgroomingkit'] = {
        label = 'Pet Grooming Kit',
        weight = 500,
        stack = false,
        close = true,
        description = 'Now your pet can pass a wave check.',
    },
    -- PenguRP: end keep-companion-ox items
}
