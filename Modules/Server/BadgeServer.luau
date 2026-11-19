--!strict
--[[
    BadgeServer: awards Roblox badges (BadgeConfig) from gameplay events. A badge whose Id is
    still 0 (not created yet) is skipped; event badges are earned the next time the event
    happens, and jet / mastery badges are re-checked on every join so those are never lost.

    Profile key "Badges" = { [key] = true } once BadgeService confirmed the award.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local BadgeService = game:GetService("BadgeService")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local BadgeConfig = require(ReplicatedStorage.Config.BadgeConfig)
local MasteryConfig = require(ReplicatedStorage.Config.MasteryConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)

local Badge = ModuleUtil.New({})
local Economy: any, Analytics: any
local tBusy: { [Player]: { [string]: boolean } } = {}

function Badge.Award(self, p: Player, key: string)
	local b = BadgeConfig.Badges[key]
	if not b or b.Id == 0 or not p.Parent then return end
	local have = mProfile:GetAsync(p, "Badges") or {}
	if have[key] then return end
	tBusy[p] = tBusy[p] or {}
	if tBusy[p][key] then return end
	tBusy[p][key] = true
	task.spawn(function()
		local ok, res = pcall(BadgeService.AwardBadge, BadgeService, p.UserId, b.Id)
		if not ok then
			-- already owned (e.g. profile reset) counts as done; anything else retries next time
			local okHas, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, p.UserId, b.Id)
			ok, res = okHas and has, okHas and has
		end
		if ok and res and p.Parent then
			Economy:SetProfileKey(p, "Badges", function(v) v = v or {}; v[key] = true; return v end)
			Analytics:Log(p, "badge_awarded", { badge = key })
		end
		if tBusy[p] then tBusy[p][key] = nil end
	end)
end

local REWARD_BADGES = {
	Kill = "FirstKill",
	SonicBoom = "MachOne",
	CarrierTrap = "CarrierTrap",
	BountyClaim = "BountyHunter",
	FortressShare = "Fortress",
}

local function checkOwned(self, p: Player)
	local owned = mProfile:GetAsync(p, "OwnedJets") or {}
	for jetId, key in pairs(BadgeConfig.JetBadges) do
		if owned[jetId] then self:Award(p, key) end
	end
	local passes = {}
	local okM, Mon = pcall(require, ServerStorage.ServerModules:FindFirstChild("MonetizationServer") :: any)
	if okM and Mon and Mon.GetPasses then passes = Mon:GetPasses(p) end
	if passes.WraithX then self:Award(p, "Wraith") end
	for _, xp in pairs(mProfile:GetAsync(p, "Mastery") or {}) do
		if MasteryConfig.LevelFor(xp) >= MasteryConfig.MaxLevel then self:Award(p, "Mastery"); break end
	end
end

function Badge.StartAsync(self)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	local Flight = require(ServerStorage.ServerModules.FlightServer)
	local MasteryS = require(ServerStorage.ServerModules.MasteryServer)

	Flight.OnLaunched.Event:Connect(function(p: Player) self:Award(p, "Welcome") end)
	Economy.OnReward.Event:Connect(function(p: Player, key: string)
		local b = REWARD_BADGES[key]
		if b then self:Award(p, b) end
	end)
	Economy.OnMultiKill.Event:Connect(function(p: Player, n: number) if n >= 3 then self:Award(p, "MultiKill") end end)
	Economy.OnJetUnlocked.Event:Connect(function(p: Player, jetId: string)
		local b = BadgeConfig.JetBadges[jetId]
		if b then self:Award(p, b) end
	end)
	MasteryS.OnLevel.Event:Connect(function(p: Player, _jet: string, lvl: number)
		if lvl >= MasteryConfig.MaxLevel then self:Award(p, "Mastery") end
	end)
	local okM, Mon = pcall(require, ServerStorage.ServerModules:FindFirstChild("MonetizationServer") :: any)
	if okM and Mon and Mon.OnPassesChanged then
		Mon.OnPassesChanged.Event:Connect(function(p: Player) checkOwned(self, p) end)
	end
	-- Ace: wearing the bounty marker
	local function watch(p: Player)
		p:GetAttributeChangedSignal("Bounty"):Connect(function()
			if p:GetAttribute("Bounty") then self:Award(p, "Ace") end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
end

function Badge.InitProfileAsync(self, p: Player)
	task.delay(6, function() if p.Parent then checkOwned(self, p) end end)
end

function Badge.PlayerRemoving(self, p: Player)
	tBusy[p] = nil
end

return Badge
