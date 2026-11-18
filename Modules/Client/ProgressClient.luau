--!strict
--[[
    ProgressClient: keeps "what am I working toward" in front of the player.
      - sortie challenges (ChallengeServer) -> Store.tChallenges
      - next jet to unlock with cash (and its rank requirement) -> Store.sNextJet / nNextJetFrac
      - rank progress line -> Store.sRankLine
    Shown on the deck, on the death screen, and (challenges) as a compact list in flight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local JetConfig = require(ReplicatedStorage.Config.JetConfig)
local XPConfig = require(ReplicatedStorage.Config.XPConfig)
local Fusion = require(ReplicatedStorage.Packages.fusion)
local peek = Fusion.peek

local Progress = ModuleUtil.New({})

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function refresh()
	local cash = peek(Store.Values.nCash) :: number
	local rank = peek(Store.Values.nRank) :: number
	local prog = peek(Store.Values.nRankProgress) :: number
	local hangar = peek(Store.Values.tHangar) :: any
	local owned = (hangar and hangar.OwnedJets) or { SparrowT2 = true }
	-- next cash-buyable jet the player doesn't own yet (lowest Order)
	local nextJet: any = nil
	for _, j in pairs(JetConfig.Jets) do
		if not owned[j.Id] and (j.CashPrice or 0) > 0 and (not nextJet or j.Order < nextJet.Order) then nextJet = j end
	end
	if nextJet then
		local frac = math.clamp(cash / nextJet.CashPrice, 0, 1)
		local rankNote = if rank < nextJet.RankRequired then string.format("  ·  NEEDS RANK %d", nextJet.RankRequired) else ""
		Store.Values.sNextJet:set(string.format("NEXT JET: %s   %s / %s%s", string.upper(nextJet.DisplayName), fmt(cash), fmt(nextJet.CashPrice), rankNote))
		Store.Values.nNextJetFrac:set(frac)
	else
		Store.Values.sNextJet:set("ALL JETS UNLOCKED - UPGRADE THEM IN THE HANGAR")
		Store.Values.nNextJetFrac:set(1)
	end
	if rank >= XPConfig.MaxRank then
		Store.Values.sRankLine:set(string.format("ACE RANK %d (MAX)", rank))
	else
		local a, b = XPConfig.fLevelToXP(rank), XPConfig.fLevelToXP(rank + 1)
		local left = math.max(0, math.ceil((b - a) * (1 - prog)))
		Store.Values.sRankLine:set(string.format("ACE RANK %d  ·  %s XP TO RANK %d", rank, fmt(left), rank + 1))
	end
end

function Progress.StartAsync(self)
	Remote:GetEvent("ChallengeEvent"):OnClientEvent(function(t: any)
		if typeof(t) == "table" and t.a == "Set" and typeof(t.list) == "table" then
			Store.Values.tChallenges:set(t.list)
		end
	end)
	-- cheap poll: refresh when cash, rank or hangar data change
	task.spawn(function()
		local last = ""
		while true do
			local h = peek(Store.Values.tHangar) :: any
			local owned = 0
			if h and h.OwnedJets then for _ in pairs(h.OwnedJets) do owned += 1 end end
			local key = string.format("%d|%d|%.3f|%d", peek(Store.Values.nCash) :: number, peek(Store.Values.nRank) :: number, peek(Store.Values.nRankProgress) :: number, owned)
			if key ~= last then last = key; refresh() end
			task.wait(0.5)
		end
	end)
end

return Progress
