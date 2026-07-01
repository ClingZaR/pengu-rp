-- PenguRP Court Sessions (pengu_court) - shared config. ASCII only.

Config = {}

-- Guilty plea cuts this fraction off the sentence (mirrors pengu_mdt PLEA_GUILTY_PCT).
Config.pleaReduction = 0.25

-- Hard cap on any court sentence in real minutes (xt-prison JailPlayerById clamps to 60 too).
Config.maxSentence = 60

Config.jury = {
    enabled = true,        -- master toggle for jury trials
    size = 5,              -- how many random citizens are summoned (also the seat cap)
    min = 3,               -- fewer accepters than this = jury unavailable
    pay = 200,             -- bank payout per juror when their vote is cast
    inviteTimeout = 30000, -- ms to answer a summons; no answer = declined
    voteTimeout = 60000,   -- ms to cast a vote; no vote = juror excluded from the tally
}
