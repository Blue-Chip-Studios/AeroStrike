--[[
    XPConfig (BCDK SMXP / LMXP): Ace XP -> Ace Rank.
    XP for rank n = 250 * (n-1)^1.55. Rank 3 ~ 700 XP, rank 8 ~ 5.1k,
    rank 15 ~ 15k, rank 50 ~ 104k.
]]

local MAX_RANK = 50
local BASE = 250
local EXP = 1.55

local function fLevelToXP(nLevel: number): number
	nLevel = math.clamp(math.floor(nLevel), 1, MAX_RANK + 1)
	return math.floor(BASE * (nLevel - 1) ^ EXP)
end

local function fXPToLevel(nXP: number): number
	nXP = math.max(0, nXP or 0)
	local n = math.floor((nXP / BASE) ^ (1 / EXP)) + 1
	-- correct floating error at boundaries
	while n < MAX_RANK and fLevelToXP(n + 1) <= nXP do n += 1 end
	while n > 1 and fLevelToXP(n) > nXP do n -= 1 end
	return math.clamp(n, 1, MAX_RANK)
end

return {
	MaxRank = MAX_RANK,
	fLevelToXP = fLevelToXP,
	fXPToLevel = fXPToLevel,
}
