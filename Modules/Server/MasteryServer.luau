--!strict
--[[
    MasteryServer: per-jet mastery. Every XP award also goes into the mastery of the jet the
    pilot is flying (their equipped jet). Level-ups pay cash (MasteryConfig.Rewards), unlock
    paint schemes (equipped in the Hangar through the Shop "Paint" action) and at the max level
    award the Master Aviator badge (BadgeServer listens to OnLevel).

    Mastery replicates through the HangarReplica (profile key "Mastery").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local MasteryConfig = require(ReplicatedStorage.Config.MasteryConfig)
local JetConfig = require(ReplicatedStorage.Config.JetConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)

local Mastery = ModuleUtil.New({
	OnLevel = Instance.new("BindableEvent"), -- (player, jetId, level)
})
local Economy: any, Analytics: any

local function schemesAt(level: number): { string }
	local out = {}
	for _, s in pairs(MasteryConfig.Schemes) do
		if s.Level == level then table.insert(out, s.Name) end
	end
	return out
end

local function add(p: Player, n: number)
	local okF, Flight = pcall(require, ServerStorage.ServerModules.FlightServer)
	local s = okF and Flight.GetSortie and Flight:GetSortie(p)
	local flown = s and s.Jet and s.Jet:GetAttribute("JetId")
	local jetId = flown or mProfile:GetAsync(p, "EquippedJet")
	if not jetId or not JetConfig.Jets[jetId] or n <= 0 then return end
	local all = mProfile:GetAsync(p, "Mastery") or {}
	local before = all[jetId] or 0
	local after = before + n
	Economy:SetProfileKey(p, "Mastery", function(v) v = v or {}; v[jetId] = after; return v end)
	local l0, l1 = MasteryConfig.LevelFor(before), MasteryConfig.LevelFor(after)
	if l1 <= l0 then return end
	local name = string.upper(JetConfig.Jets[jetId].DisplayName)
	for lvl = l0 + 1, l1 do
		local r = MasteryConfig.Rewards[lvl]
		local paints = schemesAt(lvl)
		local label = `{name} MASTERY {lvl}`
		if #paints > 0 then label ..= `: {string.upper(table.concat(paints, ", "))} PAINT` end
		Economy:Reward(p, "MasteryLevel", { Bank = true, Cash = (r and r.Cash) or 0, Label = label })
		Analytics:Log(p, "mastery_level", { jet = jetId, level = lvl })
		Mastery.OnLevel:Fire(p, jetId, lvl)
	end
end

function Mastery.LevelOf(self, p: Player, jetId: string): number
	return MasteryConfig.LevelFor(((mProfile:GetAsync(p, "Mastery") or {})[jetId]) or 0)
end

function Mastery.StartAsync(self)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	Economy.OnXP.Event:Connect(function(p: Player, n: number) add(p, n) end)
end

return Mastery
