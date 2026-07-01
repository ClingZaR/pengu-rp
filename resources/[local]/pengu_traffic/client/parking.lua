-- PenguRP - Traffic & Pursuit  [PARKING TICKET]
-- One ox_target global-vehicle option for on-duty LEO to ticket a
-- stationary vehicle. Reuses PT helpers; registered ONCE at load.
-- ASCII only. luac clean.

exports.ox_target:addGlobalVehicle({
    {
        name = 'pengu_parking_ticket',
        icon = 'fas fa-receipt',
        label = 'Issue Parking Ticket',
        distance = 2.5,
        canInteract = function(entity)
            return PT.isLeoOnDuty() and GetEntitySpeed(entity) < 1.0
        end,
        onSelect = function(d)
            local plate = PT.plate(d.entity)
            local res = lib.callback.await('pengu_traffic:issueFine', false, {
                plate = plate,
                amount = Config.fines.parking,
                reason = 'Illegal parking',
                kind = 'parking',
            })
            PT.notify(res and res.msg or 'Ticket issued', res and res.ok and 'success' or 'error')
        end,
    },
})

-- Remove our target option when this resource stops.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    exports.ox_target:removeGlobalVehicle('pengu_parking_ticket')
end)
