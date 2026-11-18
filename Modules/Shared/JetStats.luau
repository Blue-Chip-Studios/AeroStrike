--!strict
--[[
    JetStats
    --------
    Effective stats = base JetConfig stats + upgrade levels + owned passes.
    Shared so the client simulates exactly what the server validates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JetConfig = require(ReplicatedStorage.Config.JetConfig)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

export type Upgrades = { Engine: number?, Fuel: number?, GSuit: number?, Flares: number?, Seeker: number? }
export type Passes = { GSuitPro: boolean?, Afterburner: boolean?, FlarePod: boolean?, MultiLock: boolean? }

local JetStats = {}

function JetStats.Compute(sJetId: string, tUp: Upgrades?, tPasses: Passes?): { [string]: any }
	local base = JetConfig.Jets[sJetId] or JetConfig.Jets[JetConfig.StarterJet]
	local s = table.clone(base.Stats) :: { [string]: any }
	local up = tUp or {}
	local fx = EconomyConfig.UpgradeEffects
	local e = up.Engine or 0
	s.MaxSpeed *= 1 + fx.Engine.MaxSpeedPct * e
	s.Accel *= 1 + fx.Engine.AccelPct * e
	local f = up.Fuel or 0
	s.Fuel *= 1 + fx.Fuel.FuelPct * f
	s.BoostBurn *= 1 + fx.Fuel.BoostBurnPct * f
	local g = up.GSuit or 0
	s.GTolerance += fx.GSuit.GTolerance * g
	s.GLocDelay = fx.GSuit.GLocDelay * g
	s.Flares += fx.Flares.Flares * (up.Flares or 0)
	local sk = up.Seeker or 0
	s.LockTime *= 1 + fx.Seeker.LockTimePct * sk
	s.MissileTurnMult = 1 + fx.Seeker.MissileTurnPct * sk

	local p = tPasses or {}
	if p.GSuitPro then
		s.GTolerance += 3
		s.NoGLoc = true
	end
	if p.Afterburner then
		s.BoostBurn *= 0.4
		s.FuelRingMult = 2
	end
	if p.FlarePod then s.Flares += 4 end
	if p.MultiLock then
		s.MultiLock = 4
		s.MissileTurnMult *= 1.25
	end
	s.Special = base.Special
	if base.Special == "TwinLock" then s.MultiLock = math.max(s.MultiLock or 1, 2) end
	return s
end

return JetStats
