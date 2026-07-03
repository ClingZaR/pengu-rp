return {
    pawnLocation = {
        {
            coords = vector3(412.34, 314.81, 103.13),
            size = vector3(1.5, 1.8, 2.0),
            heading = 207.0,
            debugPoly = false,
            distance = 3.0
        }
    },
    -- PenguRP: repriced to match the effort required to obtain each item
    pawnItems = {
        {
            item = 'goldchain',
            price = math.random(200, 400)
        },
        {
            item = 'diamond_ring',
            price = math.random(300, 600)
        },
        {
            item = 'rolex',
            price = math.random(500, 1000)
        },
        {
            item = '10kgoldchain',
            price = math.random(800, 1500)
        },
        {
            item = 'tablet',
            price = math.random(150, 300)
        },
        {
            item = 'iphone',
            price = math.random(300, 600)
        },
        {
            item = 'samsungphone',
            price = math.random(200, 400)
        },
        {
            item = 'laptop',
            price = math.random(400, 800)
        },
        -- PenguRP: markedbills from store/safe robbery fenced here at ~65% face value avg
        {
            item = 'markedbills',
            price = math.random(270, 420)
        },
        -- PenguRP: goldbar from store safes + bank heists + jewelry melting. Priced below a raw
        -- goldchain ($200-400) so melting chains is slightly worse than fencing them directly.
        {
            item = 'goldbar',
            price = math.random(150, 300)
        }
    },
    meltingItems = { -- meltTime is amount of time in minutes per item
        {
            item = 'goldchain',
            rewards = {
                {
                    item = 'goldbar',
                    amount = 2
                }
            },
            meltTime = 0.15
        },
        {
            item = 'diamond_ring',
            rewards = {
                {
                    item = 'diamond',
                    amount = 1
                },
                {
                    item = 'goldbar',
                    amount = 1
                }
            },
            meltTime = 0.15
        },
        {
            item = 'rolex',
            rewards = {
                {
                    item = 'diamond',
                    amount = 1
                },
                {
                    item = 'goldbar',
                    amount = 1
                },
                {
                    item = 'electronickit',
                    amount = 1
                }
            },
            meltTime = 0.15
        },
        {
            item = '10kgoldchain',
            rewards = {
                {
                    item = 'diamond',
                    amount = 5
                },
                {
                    item = 'goldbar',
                    amount = 1
                }
            },
            meltTime = 0.15
        },
    }
}