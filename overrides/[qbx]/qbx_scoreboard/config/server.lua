return {
    -- PenguRP: jobs shown on the scoreboard with live on-duty counts.
    -- Names must match qbx_core/shared/jobs.lua keys.
    dutyJobs = {
        {name = 'police', label = 'LSPD'},
        {name = 'bcso', label = 'BCSO'},
        {name = 'sasp', label = 'SASP'},
        {name = 'ambulance', label = 'EMS'},
        {name = 'fire', label = 'LSFD'},
        {name = 'mechanic', label = 'Mechanic'},
        {name = 'taxi', label = 'Taxi'},
        {name = 'tow', label = 'Towing'},
    },

    illegalActions = {
        storerobbery = {
            minimumPolice = 2,
            label = 'Store Robbery',
        },
        bankrobbery = {
            minimumPolice = 3,
            label = 'Bank Robbery'
        },
        jewellery = {
            minimumPolice = 2,
            label = 'Jewelry'
        },
        pacific = {
            minimumPolice = 5,
            label = 'Pacific Bank'
        },
        paleto = {
            minimumPolice = 4,
            label = 'Paleto Bay Bank'
        }
    }
}
